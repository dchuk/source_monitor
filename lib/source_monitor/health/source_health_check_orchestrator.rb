# frozen_string_literal: true

module SourceMonitor
  module Health
    # Orchestrates a source health check: runs the probe, broadcasts
    # UI updates with toast notifications, triggers a follow-up fetch
    # for degraded sources, and handles unexpected errors gracefully.
    # Extracted from SourceHealthCheckJob.
    class SourceHealthCheckOrchestrator
      DEGRADED_STATUSES = %w[declining failing].freeze

      def initialize(source)
        @source = source
      end

      def call
        result = SourceMonitor::Health::SourceHealthCheck.new(source: source).call
        broadcast_outcome(result)
        trigger_fetch_if_degraded(result)
      rescue StandardError => error
        log_error(error)
        record_unexpected_failure(error)
        broadcast_outcome(nil, error)
      end

      private

      attr_reader :source

      def trigger_fetch_if_degraded(result)
        return unless result&.success?
        return unless DEGRADED_STATUSES.include?(source.health_status.to_s)

        SourceMonitor::FetchFeedJob.perform_later(source.id, force: true)
      end

      def record_unexpected_failure(error)
        SourceMonitor::HealthCheckLog.create!(
          source: source,
          success: false,
          started_at: Time.current,
          completed_at: Time.current,
          duration_ms: 0,
          error_class: error.class.name,
          error_message: error.message
        )
      rescue StandardError
        nil
      end

      def broadcast_outcome(result, error = nil)
        SourceMonitor::Realtime.broadcast_source(source)

        message, level = toast_payload(result, error)
        return if message.blank?

        SourceMonitor::Realtime.broadcast_toast(message: message, level: level)
      end

      def toast_payload(result, error)
        if error
          return [
            "Health check failed for #{source.name}: #{error.message}",
            :error
          ]
        end

        if result&.success?
          [
            "Health check succeeded for #{source.name}.",
            :success
          ]
        else
          failure_reason = result&.error&.message
          http_status = result&.log&.http_status
          message = "Health check failed for #{source.name}"
          message += " (HTTP #{http_status})" if http_status.present?
          message += ": #{failure_reason}" if failure_reason.present?
          [
            "#{message}.",
            :error
          ]
        end
      end

      def log_error(error)
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger&.error(
          "[SourceMonitor::Health::SourceHealthCheckOrchestrator] error for source #{source.id}: #{error.class}: #{error.message}"
        )
      end
    end
  end
end
