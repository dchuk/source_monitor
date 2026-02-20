# frozen_string_literal: true

module SourceMonitor
  class SourceHealthCheckJob < ApplicationJob
    source_monitor_queue :fetch

    discard_on ActiveJob::DeserializationError

    def perform(source_id)
      source = SourceMonitor::Source.find_by(id: source_id)
      return unless source

      result = SourceMonitor::Health::SourceHealthCheck.new(source: source).call
      broadcast_outcome(source, result)
      trigger_fetch_if_degraded(source, result)
      result
    rescue StandardError => error
      Rails.logger&.error(
        "[SourceMonitor::SourceHealthCheckJob] error for source #{source_id}: #{error.class}: #{error.message}"
      ) if defined?(Rails) && Rails.respond_to?(:logger)

      record_unexpected_failure(source, error) if source
      broadcast_outcome(source, nil, error) if source
      nil
    end

    DEGRADED_STATUSES = %w[declining critical warning].freeze

    private

    def trigger_fetch_if_degraded(source, result)
      return unless result&.success?
      return unless DEGRADED_STATUSES.include?(source.health_status.to_s)

      SourceMonitor::FetchFeedJob.perform_later(source.id, force: true)
    end

    def record_unexpected_failure(source, error)
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

    def broadcast_outcome(source, result, error = nil)
      SourceMonitor::Realtime.broadcast_source(source)

      message, level = toast_payload(source, result, error)
      return if message.blank?

      SourceMonitor::Realtime.broadcast_toast(message:, level:)
    end

    def toast_payload(source, result, error)
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
  end
end
