# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module SourceMonitor
  class FetchFeedJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup { clear_enqueued_jobs }

    test "invokes the fetch runner for the source" do
      source = create_source
      runner = Minitest::Mock.new
      runner.expect(:run, :ok)

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
        SourceMonitor::FetchFeedJob.perform_now(source.id)
      end

      runner.verify
      assert_mock runner
    end

    test "retries when a concurrency error occurs with exponential backoff" do
      source = create_source

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      job = SourceMonitor::FetchFeedJob.new(source.id)

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        assert_enqueued_jobs 1 do
          begin
            job.perform_now
          rescue StandardError
            # retry_on may raise internally; allow
          end
        end
      end

      enqueued = enqueued_jobs.last
      assert_equal SourceMonitor::FetchFeedJob, enqueued[:job]
      args = enqueued[:args]
      assert_equal source.id, args.first
      force_value = args[1]&.[]("force")
      assert_includes [ nil, false ], force_value
      assert enqueued[:at].present?, "expected retry to be scheduled in the future"

      # First attempt (executions=1) should have base wait of 30s * 2^1 = 60s + up to 25% jitter
      wait_seconds = enqueued[:at] - Time.current.to_f
      assert wait_seconds >= 59, "expected at least ~60s backoff, got #{wait_seconds}"
      assert wait_seconds <= 76, "expected at most ~75s backoff (60 + 25% jitter), got #{wait_seconds}"
    end

    test "schedules retry using retry policy when a transient fetch error bubbles up" do
      source = create_source(fetch_retry_attempt: 0)
      error = SourceMonitor::Fetching::TimeoutError.new("timeout")

      stub_runner = Class.new do
        def initialize(error:, **)
          @error = error
        end

        def run
          raise @error
        end
      end

      travel_to Time.zone.local(2025, 10, 12, 10, 0, 0) do
        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new(error:) }) do
          assert_enqueued_jobs 1 do
            begin
              SourceMonitor::FetchFeedJob.perform_now(source.id)
            rescue StandardError
              # retry_job does not raise, but guard if adapters behave differently
            end
          end
        end

        enqueued = enqueued_jobs.last
        assert_equal SourceMonitor::FetchFeedJob, enqueued[:job]
        assert_equal source.id, enqueued[:args].first
        wait_seconds = enqueued[:at] - Time.current.to_f
        assert_in_delta 2.minutes.to_i, wait_seconds, 1.0

        source.reload
        assert_equal 1, source.fetch_retry_attempt
        assert_equal "queued", source.fetch_status
        assert_in_delta 2.minutes.from_now, source.next_fetch_at, 1.second
        assert_in_delta 2.minutes.from_now, source.backoff_until, 1.second
      end
    end

    test "opens circuit and does not retry when policy exhausts attempts" do
      source = create_source(fetch_retry_attempt: 2)
      error = SourceMonitor::Fetching::TimeoutError.new("timeout")

      stub_runner = Class.new do
        def initialize(error:, **)
          @error = error
        end

        def run
          raise @error
        end
      end

      travel_to Time.zone.local(2025, 10, 12, 12, 0, 0) do
        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new(error:) }) do
          assert_enqueued_jobs 0 do
            assert_raises(SourceMonitor::Fetching::TimeoutError) do
              SourceMonitor::FetchFeedJob.perform_now(source.id)
            end
          end
        end

        source.reload
        assert_equal 0, source.fetch_retry_attempt
        assert_equal "failed", source.fetch_status
        assert source.fetch_circuit_until.present?
        assert source.backoff_until.present?
        assert source.next_fetch_at.present?
        assert source.fetch_circuit_until >= Time.current
      assert_equal source.fetch_circuit_until, source.next_fetch_at
      end
    end

    test "no-ops when the source is missing" do
      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**) { flunk("runner should not be initialized") }) do
        SourceMonitor::FetchFeedJob.perform_now(-1)
      end

      assert_enqueued_jobs 0
    end

    test "skips execution when the next fetch is still in the future" do
      travel_to Time.zone.local(2025, 10, 30, 12, 0, 0) do
        source = create_source(next_fetch_at: 1.hour.from_now, fetch_status: "idle")

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**) { flunk("runner should not be initialized") }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id)
        end

        assert_enqueued_jobs 0
      end
    end

    test "executes when status is queued even if next fetch is in the future" do
      travel_to Time.zone.local(2025, 10, 30, 12, 0, 0) do
        source = create_source(next_fetch_at: 2.hours.from_now, fetch_status: "queued")

        runner = Minitest::Mock.new
        runner.expect(:run, :ok)

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id)
        end

        runner.verify
        assert_mock runner
      end
    end

    test "executes when status is fetching even if next fetch is in the future" do
      travel_to Time.zone.local(2025, 10, 30, 12, 0, 0) do
        source = create_source(next_fetch_at: 2.hours.from_now, fetch_status: "fetching")

        runner = Minitest::Mock.new
        runner.expect(:run, :ok)

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id)
        end

        runner.verify
        assert_mock runner
      end
    end

    test "executes when force is true even if next fetch is in the future" do
      travel_to Time.zone.local(2025, 10, 30, 12, 0, 0) do
        source = create_source(next_fetch_at: 2.hours.from_now, fetch_status: "idle")

        runner = Minitest::Mock.new
        runner.expect(:run, :ok)

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id, force: true)
        end

        runner.verify
        assert_mock runner
      end
    end

    test "executes when next_fetch_at is blank" do
      travel_to Time.zone.local(2025, 10, 30, 12, 0, 0) do
        source = create_source(next_fetch_at: nil, fetch_status: "idle")

        runner = Minitest::Mock.new
        runner.expect(:run, :ok)

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id)
        end

        runner.verify
        assert_mock runner
      end
    end

    test "force-fetch ConcurrencyError does not retry and resets status to idle" do
      source = create_source(fetch_status: "queued")

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        assert_no_enqueued_jobs only: SourceMonitor::FetchFeedJob do
          SourceMonitor::FetchFeedJob.perform_now(source.id, force: true)
        end
      end

      source.reload
      assert_equal "idle", source.fetch_status
    end

    test "force-fetch ConcurrencyError does not reset status when not queued" do
      source = create_source(fetch_status: "fetching")

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        assert_no_enqueued_jobs only: SourceMonitor::FetchFeedJob do
          SourceMonitor::FetchFeedJob.perform_now(source.id, force: true)
        end
      end

      source.reload
      assert_equal "fetching", source.fetch_status
    end

    test "scheduled ConcurrencyError retries on first attempt" do
      source = create_source

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      # Simulate exhausting all retries by setting executions high
      job = SourceMonitor::FetchFeedJob.new(source.id)

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        # First execution should retry
        assert_enqueued_jobs 1 do
          begin
            job.perform_now
          rescue StandardError
            nil
          end
        end
      end

      enqueued = enqueued_jobs.last
      assert_equal SourceMonitor::FetchFeedJob, enqueued[:job]
      assert enqueued[:at].present?, "expected retry to be scheduled in the future"
    end

    test "concurrency error discards job after exhausting max attempts" do
      source = create_source(fetch_status: "queued")

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      job = SourceMonitor::FetchFeedJob.new(source.id)
      # Simulate having already retried the max number of times
      max = SourceMonitor::FetchFeedJob::SCHEDULED_CONCURRENCY_MAX_ATTEMPTS
      job.define_singleton_method(:executions) { max }

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        assert_nothing_raised do
          job.perform_now
        end
      end

      source.reload
      assert_equal "idle", source.fetch_status
    end

    test "concurrency backoff increases exponentially with jitter" do
      source = create_source
      job = SourceMonitor::FetchFeedJob.new(source.id)
      job.instance_variable_set(:@source_id, source.id)

      # Attempt 0: base * 2^0 = 30s, jitter up to 7.5s => 30-37.5s
      wait_0 = job.send(:concurrency_backoff_wait, 0).to_i
      assert_operator wait_0, :>=, 30
      assert_operator wait_0, :<=, 38

      # Attempt 1: base * 2^1 = 60s, jitter up to 15s => 60-75s
      wait_1 = job.send(:concurrency_backoff_wait, 1).to_i
      assert_operator wait_1, :>=, 60
      assert_operator wait_1, :<=, 75

      # Attempt 2: base * 2^2 = 120s, jitter up to 30s => 120-150s
      wait_2 = job.send(:concurrency_backoff_wait, 2).to_i
      assert_operator wait_2, :>=, 120
      assert_operator wait_2, :<=, 150

      # Attempt 3: base * 2^3 = 240s, jitter up to 60s => 240-300s
      wait_3 = job.send(:concurrency_backoff_wait, 3).to_i
      assert_operator wait_3, :>=, 240
      assert_operator wait_3, :<=, 300

      # Attempt 4: base * 2^4 = 480s, capped at 300s, jitter up to 75s => 300-375s
      wait_4 = job.send(:concurrency_backoff_wait, 4).to_i
      assert_operator wait_4, :>=, 300
      assert_operator wait_4, :<=, 375
    end

    test "concurrency exhaustion does not reset status when not queued" do
      source = create_source(fetch_status: "fetching")

      stub_runner = Class.new do
        def initialize(**); end

        def run
          raise SourceMonitor::Fetching::FetchRunner::ConcurrencyError, "locked"
        end
      end

      job = SourceMonitor::FetchFeedJob.new(source.id)
      max = SourceMonitor::FetchFeedJob::SCHEDULED_CONCURRENCY_MAX_ATTEMPTS
      job.define_singleton_method(:executions) { max }

      SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { stub_runner.new }) do
        assert_nothing_raised do
          job.perform_now
        end
      end

      source.reload
      assert_equal "fetching", source.fetch_status
    end

    test "log_concurrency_exhausted rescues StandardError" do
      source = create_source
      job = SourceMonitor::FetchFeedJob.new(source.id)
      job.instance_variable_set(:@source_id, source.id)

      fake_logger = Object.new
      def fake_logger.info(_msg)
        raise StandardError, "logger broken"
      end

      Rails.stub(:logger, fake_logger) do
        result = job.send(:log_concurrency_exhausted)
        assert_nil result
      end
    end

    test "log_force_fetch_skipped rescues StandardError" do
      source = create_source

      job = SourceMonitor::FetchFeedJob.new(source.id, force: true)
      job.instance_variable_set(:@source_id, source.id)

      # Stub Rails.logger to raise inside the logging method
      fake_logger = Object.new
      def fake_logger.info(_msg)
        raise StandardError, "logger broken"
      end

      Rails.stub(:logger, fake_logger) do
        # log_force_fetch_skipped should rescue and return nil
        result = job.send(:log_force_fetch_skipped)
        assert_nil result
      end
    end

    test "executes when next_fetch_at is within early execution leeway" do
      now = Time.zone.local(2025, 10, 30, 12, 0, 0)
      travel_to(now) do
        leeway = SourceMonitor::FetchFeedJob::EARLY_EXECUTION_LEEWAY
        source = create_source(next_fetch_at: now + (leeway - 10.seconds), fetch_status: "idle")

        runner = Minitest::Mock.new
        runner.expect(:run, :ok)

        SourceMonitor::Fetching::FetchRunner.stub(:new, ->(**_kwargs) { runner }) do
          SourceMonitor::FetchFeedJob.perform_now(source.id)
        end

        runner.verify
        assert_mock runner
      end
    end

    private

    def create_source(attributes = {})
      create_source!(
        { name: "Example Source" }.merge(attributes)
      )
    end
  end
end
