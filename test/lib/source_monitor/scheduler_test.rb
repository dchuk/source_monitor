# frozen_string_literal: true

require "test_helper"
require "securerandom"

module SourceMonitor
  class SchedulerTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      SourceMonitor::Item.delete_all
      SourceMonitor::Source.delete_all
      clear_enqueued_jobs
    end

    teardown do
      clear_enqueued_jobs
    end

    test "enqueues fetch jobs for sources due for fetch" do
      now = Time.current
      due_one = create_source(next_fetch_at: now - 5.minutes)
      due_two = create_source(next_fetch_at: nil)
      _future = create_source(next_fetch_at: now + 30.minutes)

      assert_enqueued_jobs 0

      travel_to(now) do
        assert_difference -> { enqueued_jobs.size }, 2 do
          SourceMonitor::Scheduler.run(limit: nil)
        end
      end

      job_args = enqueued_jobs.map { |job| job[:args] }
      assert_equal 2, job_args.size

      normalized = job_args.map do |args|
        { id: args.first, force: args.last["force"] }
      end

      assert_includes normalized, { id: due_one.id, force: false }
      assert_includes normalized, { id: due_two.id, force: false }
    end

    test "uses skip locked when selecting due sources" do
      now = Time.current
      create_source(next_fetch_at: now - 1.minute)

      sql = capture_sql do
        SourceMonitor::Scheduler.run(limit: 1, now: now)
      end

      assert sql.any? { |statement| statement =~ /FOR UPDATE SKIP LOCKED/i }, "expected due source query to use SKIP LOCKED"
    end

    test "returns number of sources enqueued" do
      now = Time.current
      create_source(next_fetch_at: now - 1.minute)

      travel_to(now) do
        assert_equal 1, SourceMonitor::Scheduler.run(limit: nil)
      end
    end

    test "invokes stalled fetch reconciler before scheduling sources" do
      now = Time.current
      called = false

      stubbed_result = SourceMonitor::Fetching::StalledFetchReconciler::Result.new(
        recovered_source_ids: [],
        jobs_removed: [],
        executed_at: now
      )

      SourceMonitor::Fetching::StalledFetchReconciler.stub(:call, ->(**args) do
        called = true
        assert_equal now, args[:now]
        assert_equal SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT, args[:stale_after]
        stubbed_result
      end) do
        travel_to(now) do
          SourceMonitor::Scheduler.run(limit: nil, now: now)
        end
      end

      assert called, "expected stalled fetch reconciler to be invoked"
    end

    test "skips sources already marked as queued" do
      now = Time.current
      source = create_source(next_fetch_at: now - 5.minutes, fetch_status: "queued")
      source.update_columns(updated_at: now)

      travel_to(now) do
        assert_no_difference -> { enqueued_jobs.size } do
          SourceMonitor::Scheduler.run(limit: nil)
        end
      end
    end

    test "re-enqueues sources stuck in queued state beyond timeout" do
      now = Time.current
      source = create_source(next_fetch_at: now - 1.hour, fetch_status: "queued")
      stale_time = now - (SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT + 5.minutes)
      source.update_columns(updated_at: stale_time)

      travel_to(now) do
        assert_difference -> { enqueued_jobs.size }, 1 do
          SourceMonitor::Scheduler.run(limit: nil)
        end
      end
    end

    test "includes sources with failed status in eligible fetch statuses" do
      now = Time.current
      failed_source = create_source(next_fetch_at: now - 5.minutes, fetch_status: "failed")
      idle_source = create_source(next_fetch_at: now - 5.minutes, fetch_status: "idle")

      travel_to(now) do
        assert_difference -> { enqueued_jobs.size }, 2 do
          SourceMonitor::Scheduler.run(limit: nil)
        end
      end

      job_args = enqueued_jobs.map { |job| job[:args].first }
      assert_includes job_args, failed_source.id
      assert_includes job_args, idle_source.id
    end

    test "fetch_status_predicate executes all code paths through scheduler run" do
      now = Time.current
      idle_source = create_source(next_fetch_at: now - 5.minutes, fetch_status: "idle")
      failed_source = create_source(next_fetch_at: now - 5.minutes, fetch_status: "failed")
      stale_queued_source = create_source(next_fetch_at: now - 1.hour, fetch_status: "queued")
      stale_time = now - (SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT + 5.minutes)
      stale_queued_source.update_columns(updated_at: stale_time)

      travel_to(now) do
        assert_difference -> { enqueued_jobs.size }, 3 do
          SourceMonitor::Scheduler.run(limit: nil, now: now)
        end
      end

      job_args = enqueued_jobs.map { |job| job[:args].first }
      assert_includes job_args, idle_source.id
      assert_includes job_args, failed_source.id
      assert_includes job_args, stale_queued_source.id
    end

    test "fetch_status_predicate builds correct arel conditions" do
      now = Time.current
      scheduler = SourceMonitor::Scheduler.new(limit: 10, now: now)

      # Explicitly call the predicate to ensure SimpleCov tracks execution
      predicate = scheduler.send(:fetch_status_predicate)

      # Verify it's an Arel node
      assert predicate.is_a?(Arel::Nodes::Node)

      # Create test sources to verify the predicate works correctly
      idle = create_source(fetch_status: "idle", next_fetch_at: now - 5.minutes)
      failed = create_source(fetch_status: "failed", next_fetch_at: now - 5.minutes)
      queued_recent = create_source(fetch_status: "queued", next_fetch_at: now - 5.minutes)
      queued_stale = create_source(fetch_status: "queued", next_fetch_at: now - 5.minutes)

      queued_recent.update_columns(updated_at: now)
      queued_stale.update_columns(updated_at: now - (SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT + 2.minutes))

      # Apply the predicate and verify results
      ids = SourceMonitor::Source.where(predicate).pluck(:id)

      assert_includes ids, idle.id, "should include idle sources"
      assert_includes ids, failed.id, "should include failed sources"
      assert_includes ids, queued_stale.id, "should include stale queued sources"
      refute_includes ids, queued_recent.id, "should not include recent queued sources"
    end

    test "fetch status predicate includes eligible and stale queued sources through scheduler" do
      now = Time.current
      idle = create_source(next_fetch_at: now - 5.minutes, fetch_status: "idle")
      failed = create_source(next_fetch_at: now - 5.minutes, fetch_status: "failed")
      queued_recent = create_source(next_fetch_at: now - 5.minutes, fetch_status: "queued")
      queued_stale = create_source(next_fetch_at: now - 5.minutes, fetch_status: "queued")

      queued_recent.update_columns(updated_at: now)
      queued_stale.update_columns(updated_at: now - (SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT + 2.minutes))

      travel_to(now) do
        assert_difference -> { enqueued_jobs.size }, 3 do
          SourceMonitor::Scheduler.run(limit: nil, now: now)
        end
      end

      job_args = enqueued_jobs.map { |job| job[:args].first }
      assert_includes job_args, idle.id
      assert_includes job_args, failed.id
      assert_includes job_args, queued_stale.id
      refute_includes job_args, queued_recent.id
    end

    test "includes stale fetching sources in eligible predicate" do
      now = Time.current
      stale_fetching = create_source(
        next_fetch_at: now - 10.minutes,
        fetch_status: "fetching",
        last_fetch_started_at: now - (SourceMonitor::Scheduler::STALE_QUEUE_TIMEOUT + 5.minutes)
      )
      fresh_fetching = create_source(
        next_fetch_at: now - 10.minutes,
        fetch_status: "fetching",
        last_fetch_started_at: now - 2.minutes
      )

      SourceMonitor::Fetching::StalledFetchReconciler.stub(:call, SourceMonitor::Fetching::StalledFetchReconciler::Result.new(recovered_source_ids: [], jobs_removed: [], executed_at: now)) do
        travel_to(now) do
          SourceMonitor::Scheduler.run(limit: nil, now: now)
        end
      end

      job_ids = enqueued_jobs.map { |job| job[:args].first }
      assert_includes job_ids, stale_fetching.id
      refute_includes job_ids, fresh_fetching.id
    end

    test "instruments scheduler runs and updates metrics" do
      SourceMonitor::Metrics.reset!
      now = Time.current
      create_source(next_fetch_at: now - 1.minute)

      events = []
      subscription = ActiveSupport::Notifications.subscribe("source_monitor.scheduler.run") do |*args|
        events << args.last
      end

      travel_to(now) do
        SourceMonitor::Scheduler.run(limit: nil)
      end

      assert_equal 1, events.size
      payload = events.first
      assert_equal 1, payload[:enqueued_count]
      assert payload[:duration_ms].is_a?(Numeric)

      snapshot = SourceMonitor::Metrics.snapshot
      assert_equal 1, snapshot[:counters]["scheduler_runs_total"]
      assert_equal 1, snapshot[:counters]["scheduler_sources_enqueued_total"]
      assert_equal 1, snapshot[:gauges]["scheduler_last_enqueued_count"]
      assert snapshot[:gauges]["scheduler_last_duration_ms"] >= 0
      assert snapshot[:gauges]["scheduler_last_run_at_epoch"].positive?
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription) if subscription
      SourceMonitor::Metrics.reset!
    end

  private

    def create_source(overrides = {})
      defaults = {
        name: "Source #{SecureRandom.hex(4)}",
        feed_url: "https://example.com/feed-#{SecureRandom.hex(8)}.xml",
        website_url: "https://example.com",
        fetch_interval_minutes: 60,
        active: true
      }

      create_source!(defaults.merge(overrides))
    end

    def capture_sql
      statements = []
      callback = lambda do |_, _, _, _, payload|
        statements << payload[:sql] if payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        yield
      end

      statements
    end
  end
end
