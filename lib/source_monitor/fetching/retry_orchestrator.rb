# frozen_string_literal: true

module SourceMonitor
  module Fetching
    # Executes retry/circuit-breaker decisions produced by RetryPolicy.
    #
    # Accepts a source, the original fetch error, and a RetryPolicy::Decision,
    # then either enqueues a retry job, opens the circuit, or resets retry state.
    #
    # Returns a Result struct indicating which path was taken.
    class RetryOrchestrator
      Result = Struct.new(:status, :source, :error, :decision, keyword_init: true) do
        def retry_enqueued?
          status == :retry_enqueued
        end

        def circuit_opened?
          status == :circuit_opened
        end

        def exhausted?
          status == :exhausted
        end
      end

      def self.call(source:, error:, decision:, job_class: SourceMonitor::FetchFeedJob, now: Time.current)
        new(source:, error:, decision:, job_class:, now:).call
      end

      def initialize(source:, error:, decision:, job_class:, now:)
        @source = source
        @error = error
        @decision = decision
        @job_class = job_class
        @now = now
      end

      def call
        if decision.retry?
          enqueue_retry!
        elsif decision.open_circuit?
          open_circuit!
        else
          reset_retry_state!
        end
      end

      private

      attr_reader :source, :error, :decision, :job_class, :now

      def enqueue_retry!
        retry_at = now + (decision.wait || 0)

        source.with_lock do
          source.reload
          source.update!(
            fetch_retry_attempt: decision.next_attempt,
            fetch_circuit_opened_at: nil,
            fetch_circuit_until: nil,
            next_fetch_at: retry_at,
            backoff_until: retry_at,
            fetch_status: "queued"
          )
        end

        job_class.set(wait: decision.wait || 0).perform_later(source.id)

        Result.new(status: :retry_enqueued, source: source, error: error, decision: decision)
      end

      def open_circuit!
        source.with_lock do
          source.reload
          source.update!(
            fetch_retry_attempt: 0,
            fetch_circuit_opened_at: now,
            fetch_circuit_until: decision.circuit_until,
            next_fetch_at: decision.circuit_until,
            backoff_until: decision.circuit_until,
            fetch_status: "failed"
          )
        end

        Result.new(status: :circuit_opened, source: source, error: error, decision: decision)
      end

      def reset_retry_state!
        source.with_lock do
          source.reload
          source.update!(
            fetch_retry_attempt: 0,
            fetch_circuit_opened_at: nil,
            fetch_circuit_until: nil
          )
        end

        Result.new(status: :exhausted, source: source, error: error, decision: decision)
      end
    end
  end
end
