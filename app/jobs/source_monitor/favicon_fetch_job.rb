# frozen_string_literal: true

module SourceMonitor
  class FaviconFetchJob < ApplicationJob
    TRANSIENT_ERRORS = [
      Timeout::Error, Errno::ETIMEDOUT,
      Faraday::TimeoutError, Faraday::ConnectionFailed,
      Net::OpenTimeout, Net::ReadTimeout
    ].freeze

    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    def perform(source_id)
      return unless defined?(ActiveStorage)

      source = SourceMonitor::Source.find_by(id: source_id)
      return unless source
      return unless SourceMonitor.config.favicons.enabled?
      return if source.website_url.blank?
      return if source.favicon.attached?
      return if within_cooldown?(source)

      result = SourceMonitor::Favicons::Discoverer.new(source.website_url).call

      if result
        attach_favicon(source, result)
      else
        record_failed_attempt(source)
      end
    rescue ActiveRecord::Deadlocked
      raise # let job framework retry on database deadlock
    rescue *TRANSIENT_ERRORS => error
      log_transient_error(source, error)
      raise # re-raise so job framework can retry
    rescue StandardError => error
      record_failed_attempt(source) if source
      log_error(source, error)
    end

    private

    def within_cooldown?(source)
      last_attempt = source.metadata&.dig("favicon_last_attempted_at")
      return false if last_attempt.blank?

      cooldown_days = SourceMonitor.config.favicons.retry_cooldown_days
      Time.parse(last_attempt) > cooldown_days.days.ago
    rescue ArgumentError, TypeError
      false
    end

    def attach_favicon(source, result)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: result.io,
        filename: result.filename,
        content_type: result.content_type
      )
      source.favicon.attach(blob)
    end

    def record_failed_attempt(source)
      metadata = (source.metadata || {}).merge(
        "favicon_last_attempted_at" => Time.current.iso8601
      )
      source.update_column(:metadata, metadata)
    rescue StandardError
      nil
    end

    def log_transient_error(source, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn(
        "[SourceMonitor::FaviconFetchJob] Transient error for source #{source&.id}: #{error.class} - #{error.message}"
      )
    rescue StandardError
      nil
    end

    def log_error(source, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn(
        "[SourceMonitor::FaviconFetchJob] Failed for source #{source&.id}: #{error.class} - #{error.message}"
      )
    rescue StandardError
      nil
    end
  end
end
