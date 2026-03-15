# frozen_string_literal: true

module SourceMonitor
  class ImportSessionHealthCheckJob < ApplicationJob
    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    rescue_from ActiveRecord::Deadlocked do |error|
      Rails.logger&.warn("[SourceMonitor::ImportSessionHealthCheckJob] Deadlock: #{error.message}")
      retry_job(wait: 2.seconds + rand(3).seconds)
    end

    def perform(import_session_id, entry_id)
      import_session = SourceMonitor::ImportSession.find_by(id: import_session_id)
      return unless import_session

      SourceMonitor::ImportSessions::HealthCheckUpdater.new(
        import_session: import_session,
        entry_id: entry_id
      ).call
    rescue ActiveRecord::Deadlocked
      raise # re-raise so rescue_from handler catches it
    rescue StandardError => error
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error(
          "[SourceMonitor::ImportSessionHealthCheckJob] #{error.class}: #{error.message}"
        )
      end
    end
  end
end
