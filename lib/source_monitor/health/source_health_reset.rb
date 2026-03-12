# frozen_string_literal: true

module SourceMonitor
  module Health
    class SourceHealthReset
      def self.call(source:, now: Time.current)
        new(source:, now:).call
      end

      def initialize(source:, now: Time.current)
        @source = source
        @now = now
      end

      def call
        return unless source

        source.with_lock do
          source.update!(reset_attributes)
        end
      end

      private

      attr_reader :source, :now

      def reset_attributes
        {
          health_status: "working",
          auto_paused_at: nil,
          auto_paused_until: nil,
          rolling_success_rate: nil,
          failure_count: 0,
          last_error: nil,
          last_error_at: nil,
          backoff_until: nil,
          fetch_status: "idle",
          fetch_retry_attempt: 0,
          fetch_circuit_opened_at: nil,
          fetch_circuit_until: nil,
          next_fetch_at: computed_next_fetch_at,
          updated_at: now
        }
      end

      def computed_next_fetch_at
        minutes = effective_fetch_interval_minutes
        return nil unless minutes

        now + minutes.minutes
      end

      def effective_fetch_interval_minutes
        explicit = source.fetch_interval_minutes
        return normalize_interval(explicit) if explicit.present?

        SourceMonitor.config.fetching.min_interval_minutes
      end

      def normalize_interval(value)
        return nil if value.nil?

        integer = value.to_i
        integer.positive? ? integer : nil
      end
    end
  end
end
