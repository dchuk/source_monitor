# frozen_string_literal: true

require "test_helper"
require_relative "../../support/shared_loggable_tests"

module SourceMonitor
  class FetchLogTest < ActiveSupport::TestCase
    include SharedLoggableTests

    setup do
      @source = Source.create!(name: "Example", feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml")
    end

    def build_loggable(overrides = {})
      FetchLog.new({ source: @source, started_at: Time.current }.merge(overrides))
    end

    test "creates log with metrics" do
      log = FetchLog.new(
        source: @source,
        success: true,
        items_created: 5,
        items_updated: 2,
        items_failed: 1,
        started_at: Time.current,
        completed_at: 1.minute.from_now,
        duration_ms: 60000,
        http_status: 200,
        http_response_headers: { "Content-Type" => "application/rss+xml" },
        metadata: { attempt: 1 }
      )

      assert log.save
      assert log.success
      assert_equal 5, log.items_created
    end

    test "validates non-negative counts" do
      log = FetchLog.new(source: @source, started_at: Time.current, items_created: -1)

      assert_not log.valid?
      assert_includes log.errors[:items_created], "must be greater than or equal to 0"
    end

    test "scopes filter by outcome and recency" do
      successful = FetchLog.create!(source: @source, success: true, started_at: 5.minutes.ago)
      failed = FetchLog.create!(source: @source, success: false, started_at: 2.minutes.ago)
      older = FetchLog.create!(source: @source, success: true, started_at: 10.minutes.ago)

      source_logs = FetchLog.where(source: @source)
      assert_equal [ failed, successful, older ], source_logs.recent.to_a
      assert_equal [ successful, older ], source_logs.successful.to_a
      assert_equal [ failed ], source_logs.failed.to_a
    end

    test "scopes by job id" do
      tracked = FetchLog.create!(source: @source, job_id: "abc-123", started_at: Time.current)
      FetchLog.create!(source: @source, job_id: "other", started_at: Time.current)

      assert_equal [ tracked ], FetchLog.for_job("abc-123").to_a
    end

    test "validates error_category inclusion" do
      log = FetchLog.new(source: @source, started_at: Time.current, error_category: "invalid")
      assert_not log.valid?
      assert_includes log.errors[:error_category], "is not included in the list"
    end

    test "allows nil error_category" do
      log = FetchLog.new(source: @source, started_at: Time.current, error_category: nil)
      assert log.valid?
    end

    test "allows valid error_category values" do
      %w[network parse blocked auth unknown].each do |category|
        log = FetchLog.new(source: @source, started_at: Time.current, error_category: category)
        assert log.valid?, "Expected error_category '#{category}' to be valid"
      end
    end

    test "sync_log_entry creates LogEntry via Loggable concern" do
      fetch_log = FetchLog.create!(source: @source, started_at: Time.current, success: true)

      log_entry = SourceMonitor::LogEntry.find_by(loggable: fetch_log)
      assert log_entry.present?, "LogEntry should be created by sync_log_entry callback in Loggable concern"
      assert_equal @source.id, log_entry.source_id
      assert_equal "SourceMonitor::FetchLog", log_entry.loggable_type
    end

    test "by_category scope filters logs" do
      network_log = FetchLog.create!(source: @source, success: false, started_at: 3.minutes.ago, error_category: "network")
      blocked_log = FetchLog.create!(source: @source, success: false, started_at: 2.minutes.ago, error_category: "blocked")
      FetchLog.create!(source: @source, success: true, started_at: 1.minute.ago, error_category: nil)

      assert_equal [ network_log ], FetchLog.by_category("network").to_a
      assert_equal [ blocked_log ], FetchLog.by_category("blocked").to_a
      assert_empty FetchLog.by_category("auth").to_a
    end
  end
end
