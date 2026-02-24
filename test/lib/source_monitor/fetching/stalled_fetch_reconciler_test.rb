# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class StalledFetchReconcilerTest < ActiveSupport::TestCase
      STALE_THRESHOLD = SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT

      setup do
        cleanup_solid_queue_tables
      end

      teardown do
        cleanup_solid_queue_tables
      end

      test "recovers stale fetching source, discards failed executions, and re-enqueues fetch" do
        now = Time.current
        source = create_source!(
          fetch_status: "fetching",
          last_fetch_started_at: now - (STALE_THRESHOLD + 5.minutes),
          next_fetch_at: now - 3.hours,
          failure_count: 0,
          last_error: nil,
          last_error_at: nil
        )

        job = enqueue_fetch_job_for(source)
        # Simulate the in-flight state the UI observed
        failure_error = {
          "exception_class" => "SolidQueue::Processes::ProcessExitError",
          "message" => "Process exited unexpectedly",
          "backtrace" => nil
        }
        SolidQueue::FailedExecution.create!(job:, error: failure_error)

        source.update_columns(
          fetch_status: "fetching",
          last_fetch_started_at: now - (STALE_THRESHOLD + 5.minutes),
          updated_at: now - (STALE_THRESHOLD + 5.minutes)
        )

        result = nil
        with_queue_adapter(:solid_queue) do
          result = SourceMonitor::Fetching::StalledFetchReconciler.call(now:, stale_after: STALE_THRESHOLD)
        end

        source.reload
        assert_equal [ source.id ], result.recovered_source_ids
        assert_equal "queued", source.fetch_status
        assert source.last_error.present?, "expected last_error to be set"
        assert_equal now.to_i, result.executed_at.to_i
        assert_nil SolidQueue::FailedExecution.find_by(job_id: job.id), "expected failed execution to be discarded"

        matching_jobs = SolidQueue::Job.where(queue_name: SourceMonitor.queue_name(:fetch)).
          where("arguments::jsonb -> 'arguments' ->> 0 = ?", source.id.to_s)
        assert_equal 1, matching_jobs.count, "expected a single fresh job in the fetch queue"
      end

    test "ignores fetching sources that have not reached the stale threshold" do
      now = Time.current
      source = create_source!(
        fetch_status: "fetching",
        last_fetch_started_at: now - 2.minutes,
        next_fetch_at: now - 30.minutes
        )

        enqueue_fetch_job_for(source)
        source.update_columns(fetch_status: "fetching", last_fetch_started_at: now - 2.minutes)

        result = nil
        with_queue_adapter(:solid_queue) do
          result = SourceMonitor::Fetching::StalledFetchReconciler.call(now:, stale_after: STALE_THRESHOLD)
        end

        source.reload
      assert_equal "fetching", source.fetch_status
      assert_empty result.recovered_source_ids
    end

    test "default stale_after uses configured stale timeout" do
      assert_equal SourceMonitor.config.fetching.stale_timeout_minutes.minutes,
        SourceMonitor::Fetching::StalledFetchReconciler.send(:default_stale_after)
    end

    test "default stale_after falls back to ten minutes when config unavailable" do
      broken_fetching = Object.new
      def broken_fetching.stale_timeout_minutes
        raise NoMethodError, "undefined method"
      end
      broken_config = Object.new
      broken_config.define_singleton_method(:fetching) { broken_fetching }

      SourceMonitor.stub(:config, broken_config) do
        assert_equal 10.minutes, SourceMonitor::Fetching::StalledFetchReconciler.send(:default_stale_after)
      end
    end

    test "recover_source logs and swallows unexpected errors" do
      now = Time.current
      source = create_source!(
        fetch_status: "fetching",
        last_fetch_started_at: now - (STALE_THRESHOLD + 1.minute)
      )

      reconciler = SourceMonitor::Fetching::StalledFetchReconciler.send(:new, now:, stale_after: STALE_THRESHOLD)
      logger = Minitest::Mock.new
      logger.expect(:error, nil, [ String ])

      source.define_singleton_method(:with_lock) do |&block|
        raise StandardError, "lock failure"
      end

      result = Rails.stub(:logger, logger) do
        reconciler.send(:recover_source, source, jobs_supported: false)
      end

      logger.verify
      assert_nil result
    end

    test "discard_jobs_for destroys jobs without failed executions" do
      now = Time.current
      source = create_source!(
        fetch_status: "fetching",
        last_fetch_started_at: now - (STALE_THRESHOLD + 1.minute)
      )

      enqueue_fetch_job_for(source)

      reconciler = SourceMonitor::Fetching::StalledFetchReconciler.send(:new, now:, stale_after: STALE_THRESHOLD)

      assert_difference -> { SolidQueue::Job.count }, -1 do
        reconciler.send(:discard_jobs_for, source)
      end
    end

    test "jobs_supported? returns false when Solid Queue tables are unavailable" do
      reconciler = SourceMonitor::Fetching::StalledFetchReconciler.send(:new, now: Time.current, stale_after: 1.minute)
      error = ActiveRecord::StatementInvalid.new("boom")

      SolidQueue::Job.stub(:table_exists?, -> { raise error }) do
        refute reconciler.send(:jobs_supported?)
      end
    end

    private

      def enqueue_fetch_job_for(source)
        with_queue_adapter(:solid_queue) do
          SourceMonitor::Fetching::FetchRunner.enqueue(source.id)
        end

        SolidQueue::Job.order(:id).last
      end

      def cleanup_solid_queue_tables
        if defined?(SolidQueue::FailedExecution)
          SolidQueue::FailedExecution.delete_all
        end

        if defined?(SolidQueue::ClaimedExecution)
          SolidQueue::ClaimedExecution.delete_all
        end

        if defined?(SolidQueue::ReadyExecution)
          SolidQueue::ReadyExecution.delete_all
        end

        if defined?(SolidQueue::ScheduledExecution)
          SolidQueue::ScheduledExecution.delete_all
        end

        if defined?(SolidQueue::Job)
          SolidQueue::Job.delete_all
        end
      end
    end
  end
end
