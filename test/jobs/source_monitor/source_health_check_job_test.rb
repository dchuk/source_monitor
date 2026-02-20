# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceHealthCheckJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup { clear_enqueued_jobs }

    teardown do
      clear_enqueued_jobs
    end

    test "creates successful health check log" do
      source = create_source!(feed_url: "https://example.com/feed.xml")

      stub_request(:get, source.feed_url).to_return(status: 200, body: "", headers: { "Content-Type" => "application/rss+xml" })

      assert_enqueued_with(job: SourceMonitor::SourceHealthCheckJob, args: [ source.id ]) do
        SourceMonitor::SourceHealthCheckJob.perform_later(source.id)
      end

      perform_enqueued_jobs

      log = SourceMonitor::HealthCheckLog.order(:created_at).last
      assert_not_nil log, "expected a health check log to be created"
      assert_equal source, log.source
      assert log.success?, "expected the log to be marked as success"
      assert_equal 200, log.http_status

      entry = SourceMonitor::LogEntry.order(:created_at).last
      assert_equal log, entry.loggable
      assert entry.success?, "expected log entry to be successful"
      assert_equal "SourceMonitor::HealthCheckLog", entry.loggable_type
    end

    test "records failure details without raising" do
      source = create_source!(feed_url: "https://example.com/feed.xml")

      stub_request(:get, source.feed_url).to_timeout

      broadcasted_sources = []
      toasts = []

      SourceMonitor::Realtime.stub(:broadcast_source, ->(record) { broadcasted_sources << record }) do
        SourceMonitor::Realtime.stub(:broadcast_toast, ->(**payload) { toasts << payload }) do
          SourceMonitor::SourceHealthCheckJob.perform_later(source.id)
          perform_enqueued_jobs
        end
      end

      log = SourceMonitor::HealthCheckLog.order(:created_at).last
      assert_not_nil log, "expected failure log to be stored"
      refute log.success?
      assert_nil log.http_status
      assert_match(/expired|timeout/i, log.error_message.to_s)
      assert log.error_class.present?

      entry = SourceMonitor::LogEntry.order(:created_at).last
      assert_equal log, entry.loggable
      refute entry.success?
      assert_equal source, entry.source

      assert_equal [ source ], broadcasted_sources
      refute_empty toasts
      assert_equal :error, toasts.last[:level]
      assert_match(/Health check/i, toasts.last[:message])
    end

    test "broadcasts UI updates and toast when health check succeeds" do
      source = create_source!(feed_url: "https://example.com/feed.xml")

      stub_request(:get, source.feed_url).to_return(
        status: 200,
        body: "",
        headers: { "Content-Type" => "application/rss+xml" }
      )

      broadcasted_sources = []
      toasts = []

      SourceMonitor::Realtime.stub(:broadcast_source, ->(record) { broadcasted_sources << record }) do
        SourceMonitor::Realtime.stub(:broadcast_toast, ->(**payload) { toasts << payload }) do
          SourceMonitor::SourceHealthCheckJob.perform_later(source.id)
          perform_enqueued_jobs
        end
      end

      assert_equal [ source ], broadcasted_sources
      refute_empty toasts
      toast = toasts.last
      assert_equal :success, toast[:level]
      assert_match(/Health check/i, toast[:message])
    end

    test "records unexpected errors and broadcasts failure toast" do
      source = create_source!(feed_url: "https://example.com/feed.xml")

      broadcasts = []
      toasts = []

      failing_service = Class.new do
        def initialize(*); end

        def call
          raise StandardError, "boom"
        end
      end

      SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**) { failing_service.new }) do
        SourceMonitor::Realtime.stub(:broadcast_source, ->(record) { broadcasts << record }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**payload) { toasts << payload }) do
            SourceMonitor::SourceHealthCheckJob.perform_now(source.id)
          end
        end
      end

      log = SourceMonitor::HealthCheckLog.order(:created_at).last
      assert_equal source, log.source
      assert_equal false, log.success?
      assert_equal "boom", log.error_message

      assert_equal [ source ], broadcasts
      assert_equal :error, toasts.last[:level]
      assert_match(/failed/i, toasts.last[:message])
    end

    test "enqueues fetch when health check succeeds on declining source" do
      source = create_source!(feed_url: "https://example.com/feed.xml", health_status: "declining")

      stub_request(:get, source.feed_url).to_return(
        status: 200, body: "", headers: { "Content-Type" => "application/rss+xml" }
      )

      SourceMonitor::SourceHealthCheckJob.perform_now(source.id)

      fetch_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FetchFeedJob" }
      assert_equal 1, fetch_jobs.size, "expected FetchFeedJob to be enqueued"
      assert_equal source.id, fetch_jobs.first["arguments"].first
    end

    test "enqueues fetch when health check succeeds on critical source" do
      source = create_source!(feed_url: "https://example.com/feed.xml", health_status: "critical")

      stub_request(:get, source.feed_url).to_return(
        status: 200, body: "", headers: { "Content-Type" => "application/rss+xml" }
      )

      SourceMonitor::SourceHealthCheckJob.perform_now(source.id)

      fetch_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FetchFeedJob" }
      assert_equal 1, fetch_jobs.size, "expected FetchFeedJob to be enqueued"
    end

    test "enqueues fetch when health check succeeds on warning source" do
      source = create_source!(feed_url: "https://example.com/feed.xml", health_status: "warning")

      stub_request(:get, source.feed_url).to_return(
        status: 200, body: "", headers: { "Content-Type" => "application/rss+xml" }
      )

      SourceMonitor::SourceHealthCheckJob.perform_now(source.id)

      fetch_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FetchFeedJob" }
      assert_equal 1, fetch_jobs.size, "expected FetchFeedJob to be enqueued"
    end

    test "does not enqueue fetch when health check succeeds on healthy source" do
      source = create_source!(feed_url: "https://example.com/feed.xml", health_status: "healthy")

      stub_request(:get, source.feed_url).to_return(
        status: 200, body: "", headers: { "Content-Type" => "application/rss+xml" }
      )

      SourceMonitor::SourceHealthCheckJob.perform_now(source.id)

      fetch_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FetchFeedJob" }
      assert_empty fetch_jobs, "expected no FetchFeedJob to be enqueued for healthy source"
    end

    test "does not enqueue fetch when health check fails on degraded source" do
      source = create_source!(feed_url: "https://example.com/feed.xml", health_status: "declining")

      stub_request(:get, source.feed_url).to_timeout

      SourceMonitor::SourceHealthCheckJob.perform_now(source.id)

      fetch_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FetchFeedJob" }
      assert_empty fetch_jobs, "expected no FetchFeedJob to be enqueued after failed health check"
    end

    test "swallows logging errors when failure recording fails" do
      source = create_source!(feed_url: "https://example.com/feed.xml")

      failing_service = Class.new do
        def initialize(*); end

        def call
          raise StandardError, "boom"
        end
      end

      failing_service = Class.new do
        def initialize(*); end

        def call
          raise StandardError, "boom"
        end
      end

      SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**) { failing_service.new }) do
        SourceMonitor::HealthCheckLog.stub(:create!, ->(**) { raise StandardError, "log failure" }) do
          assert_nothing_raised do
            SourceMonitor::SourceHealthCheckJob.perform_now(source.id)
          end
        end
      end
    end
  end
end
