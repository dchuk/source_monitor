# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class FetchingSettings
      attr_accessor :min_interval_minutes,
        :max_interval_minutes,
        :increase_factor,
        :decrease_factor,
        :failure_increase_factor,
        :jitter_percent

      def initialize
        reset!
      end

      def reset!
        @min_interval_minutes = 5
        @max_interval_minutes = 24 * 60
        @increase_factor = 1.25
        @decrease_factor = 0.75
        @failure_increase_factor = 1.5
        @jitter_percent = 0.1
      end
    end
  end
end
