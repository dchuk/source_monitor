# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class HealthSettings
      attr_accessor :window_size,
        :healthy_threshold,
        :warning_threshold,
        :auto_pause_threshold,
        :auto_resume_threshold,
        :auto_pause_cooldown_minutes

      def initialize
        reset!
      end

      def reset!
        @window_size = 20
        @healthy_threshold = 0.8
        @warning_threshold = 0.5
        @auto_pause_threshold = 0.2
        @auto_resume_threshold = 0.6
        @auto_pause_cooldown_minutes = 60
      end
    end
  end
end
