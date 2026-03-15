# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class RetryOrchestratorTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @source = create_source!(name: "Retry Test Source", fetch_retry_attempt: 0)
      end

      # --- retry path ---

      test "call with retry decision enqueues FetchFeedJob and updates source state" do
        decision = RetryPolicy::Decision.new(
          retry?: true,
          wait: 2.minutes,
          next_attempt: 1,
          open_circuit?: false,
          circuit_until: nil
        )
        error = TimeoutError.new("timeout")

        travel_to Time.zone.local(2025, 11, 1, 10, 0, 0) do
          result = nil
          assert_enqueued_with(job: SourceMonitor::FetchFeedJob) do
            result = RetryOrchestrator.call(source: @source, error: error, decision: decision)
          end

          assert result.retry_enqueued?
          assert_not result.circuit_opened?
          assert_not result.exhausted?
          assert_equal :retry_enqueued, result.status

          @source.reload
          assert_equal 1, @source.fetch_retry_attempt
          assert_equal "queued", @source.fetch_status
          assert_in_delta 2.minutes.from_now, @source.next_fetch_at, 1.second
          assert_in_delta 2.minutes.from_now, @source.backoff_until, 1.second
          assert_nil @source.fetch_circuit_opened_at
          assert_nil @source.fetch_circuit_until
        end
      end

      # --- circuit-open path ---

      test "call with circuit-open decision updates source and does not enqueue retry" do
        circuit_until = 1.hour.from_now
        decision = RetryPolicy::Decision.new(
          retry?: false,
          wait: 1.hour,
          next_attempt: 0,
          open_circuit?: true,
          circuit_until: circuit_until
        )
        error = TimeoutError.new("timeout after exhausting retries")

        result = nil
        assert_no_enqueued_jobs only: SourceMonitor::FetchFeedJob do
          result = RetryOrchestrator.call(source: @source, error: error, decision: decision)
        end

        assert result.circuit_opened?
        assert_not result.retry_enqueued?
        assert_not result.exhausted?
        assert_equal :circuit_opened, result.status

        @source.reload
        assert_equal 0, @source.fetch_retry_attempt
        assert_equal "failed", @source.fetch_status
        assert @source.fetch_circuit_opened_at.present?
        assert_in_delta circuit_until.to_f, @source.fetch_circuit_until.to_f, 1
        assert_in_delta circuit_until.to_f, @source.next_fetch_at.to_f, 1
        assert_in_delta circuit_until.to_f, @source.backoff_until.to_f, 1
      end

      # --- exhausted path (neither retry nor circuit) ---

      test "call with exhausted decision resets retry state and returns exhausted" do
        @source.update!(fetch_retry_attempt: 3, fetch_circuit_opened_at: 1.hour.ago, fetch_circuit_until: 30.minutes.ago)

        decision = RetryPolicy::Decision.new(
          retry?: false,
          wait: nil,
          next_attempt: 0,
          open_circuit?: false,
          circuit_until: nil
        )
        error = TimeoutError.new("timeout")

        result = nil
        assert_no_enqueued_jobs only: SourceMonitor::FetchFeedJob do
          result = RetryOrchestrator.call(source: @source, error: error, decision: decision)
        end

        assert result.exhausted?
        assert_not result.retry_enqueued?
        assert_not result.circuit_opened?
        assert_equal :exhausted, result.status

        @source.reload
        assert_equal 0, @source.fetch_retry_attempt
        assert_nil @source.fetch_circuit_opened_at
        assert_nil @source.fetch_circuit_until
      end

      # --- atomic updates ---

      test "source updates are performed within with_lock" do
        decision = RetryPolicy::Decision.new(
          retry?: true,
          wait: 5.minutes,
          next_attempt: 1,
          open_circuit?: false,
          circuit_until: nil
        )
        error = ConnectionError.new("connection refused")

        lock_called = false
        original_with_lock = @source.method(:with_lock)
        @source.define_singleton_method(:with_lock) do |&block|
          lock_called = true
          original_with_lock.call(&block)
        end

        RetryOrchestrator.call(source: @source, error: error, decision: decision)
        assert lock_called, "Expected source.with_lock to be called"
      end

      # --- result carries context ---

      test "result carries source, error, and decision" do
        decision = RetryPolicy::Decision.new(
          retry?: true,
          wait: 2.minutes,
          next_attempt: 1,
          open_circuit?: false,
          circuit_until: nil
        )
        error = TimeoutError.new("timeout")

        result = RetryOrchestrator.call(source: @source, error: error, decision: decision)

        assert_equal @source, result.source
        assert_equal error, result.error
        assert_equal decision, result.decision
      end

      # --- custom job_class ---

      test "call enqueues using provided job_class" do
        decision = RetryPolicy::Decision.new(
          retry?: true,
          wait: 1.minute,
          next_attempt: 1,
          open_circuit?: false,
          circuit_until: nil
        )
        error = TimeoutError.new("timeout")

        fake_job_class = Class.new(ActiveJob::Base) do
          self.queue_adapter = :test
          def perform(*); end
        end

        result = RetryOrchestrator.call(
          source: @source, error: error, decision: decision,
          job_class: fake_job_class
        )

        assert result.retry_enqueued?
      end
    end
  end
end
