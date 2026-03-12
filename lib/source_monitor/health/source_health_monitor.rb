# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module SourceMonitor
  module Health
    class SourceHealthMonitor
      attr_reader :source, :config, :now

      def initialize(source:, config: SourceMonitor.config.health, now: Time.current)
        @source = source
        @config = config
        @now = now
      end

      def call
        reload_source

        logs = recent_logs.to_a
        return if logs.empty?

        rate = calculate_success_rate(logs)
        attrs = { rolling_success_rate: rate }
        sample_size = logs.size
        thresholds_active = thresholds_applicable?(sample_size)

        auto_paused_until = current_auto_paused_until
        auto_paused_at = current_auto_paused_at

        if thresholds_active && should_resume?(auto_paused_until, rate)
          auto_paused_until = nil
          auto_paused_at = nil
          attrs[:auto_paused_until] = nil
          attrs[:auto_paused_at] = nil
          attrs[:backoff_until] = nil if source.backoff_until.present?
        end

        if thresholds_active && should_auto_pause?(rate)
          new_until = compute_auto_pause_until(auto_paused_until)
          auto_paused_until = new_until
          auto_paused_at ||= now

          attrs[:auto_paused_until] = new_until
          attrs[:auto_paused_at] = auto_paused_at
          apply_backoff(attrs, new_until)
        end

        enforce_fixed_interval(attrs, auto_paused_until)

        status = determine_status(rate, auto_paused_until, logs)
        apply_status(attrs, status)

        source.update!(attrs)
      rescue ActiveRecord::RecordNotFound
        # Source was deleted between fetch and health update.
        nil
      end

      private

      def reload_source
        source.reload
      end

      def recent_logs
        limit = [ config.window_size.to_i, 1 ].max
        source.fetch_logs.order(started_at: :desc).limit(limit)
      end

      def calculate_success_rate(logs)
        successes = logs.count { |log| log.success? }
        total = logs.size
        return 0.0 if total.zero?

        (successes.to_f / total).round(4)
      end

      def current_auto_paused_until
        source.auto_paused_until
      end

      def current_auto_paused_at
        source.auto_paused_at
      end

      def should_resume?(auto_paused_until, rate)
        return false if auto_paused_until.nil?

        rate >= auto_resume_threshold
      end

      def should_auto_pause?(rate)
        threshold = auto_pause_threshold
        return false if threshold.nil?

        rate < threshold
      end

      def compute_auto_pause_until(existing_until)
        cooldown = [ config.auto_pause_cooldown_minutes.to_i, 1 ].max
        proposed = now + cooldown.minutes

        return proposed if existing_until.nil?
        existing_until > proposed ? existing_until : proposed
      end

      def apply_backoff(attrs, pause_until)
        if source.next_fetch_at.nil? || source.next_fetch_at < pause_until
          attrs[:next_fetch_at] = pause_until
        end

        if source.backoff_until.nil? || source.backoff_until < pause_until
          attrs[:backoff_until] = pause_until
        end
      end

      def determine_status(rate, _auto_paused_until, logs)
        if rate >= healthy_threshold
          "working"
        elsif rate < auto_pause_threshold
          "failing"
        elsif consecutive_failures(logs) >= 3
          "declining"
        elsif improving_streak?(logs)
          "improving"
        else
          "declining"
        end
      end

      def enforce_fixed_interval(attrs, auto_paused_until)
        return if source.adaptive_fetching_enabled?
        return if auto_paused_active?(auto_paused_until)

        backoff_value = attrs.key?(:backoff_until) ? attrs[:backoff_until] : source.backoff_until
        return if backoff_value.blank?

        fixed_minutes = [ source.fetch_interval_minutes.to_i, 1 ].max
        attrs[:next_fetch_at] = now + fixed_minutes.minutes
        attrs[:backoff_until] = nil
      end

      def apply_status(attrs, status)
        previous = source.health_status.presence || "working"
        return if previous == status

        attrs[:health_status] = status
        attrs[:health_status_changed_at] = now
      end

      def auto_pause_threshold
        value = source.health_auto_pause_threshold
        value = config.auto_pause_threshold if value.nil?
        value&.to_f
      end

      def auto_resume_threshold
        [ config.auto_resume_threshold.to_f, auto_pause_threshold.to_f ].max
      end

      def healthy_threshold
        config.healthy_threshold.to_f
      end

      def auto_paused_active?(value)
        value.present? && value.future?
      end

      def thresholds_applicable?(sample_size)
        sample_size >= minimum_sample_size
      end

      def minimum_sample_size
        [ config.window_size.to_i, 1 ].max
      end

      def consecutive_failures(logs)
        logs.take_while { |log| !log_success?(log) }.size
      end

      def improving_streak?(logs)
        success_streak = 0
        failure_seen = false

        logs.each do |log|
          if log_success?(log)
            success_streak += 1
          else
            failure_seen = true
            break
          end
        end

        success_streak >= 2 && failure_seen
      end

      def log_success?(log)
        return log.success? if log.respond_to?(:success?)

        !!log.success
      end
    end
  end
end
