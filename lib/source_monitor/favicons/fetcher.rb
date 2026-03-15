# frozen_string_literal: true

module SourceMonitor
  module Favicons
    # Coordinates favicon fetching for a source: checks prerequisites
    # (ActiveStorage, config, cooldown), delegates to Discoverer, and
    # handles attachment or failure recording. Extracted from FaviconFetchJob.
    class Fetcher
      TRANSIENT_ERRORS = [
        Timeout::Error, Errno::ETIMEDOUT,
        Faraday::TimeoutError, Faraday::ConnectionFailed,
        Net::OpenTimeout, Net::ReadTimeout
      ].freeze

      def initialize(source)
        @source = source
      end

      def call
        return unless defined?(ActiveStorage)
        return unless SourceMonitor.config.favicons.enabled?
        return if source.website_url.blank?
        return if source.favicon.attached?
        return if within_cooldown?

        result = SourceMonitor::Favicons::Discoverer.new(source.website_url).call

        if result
          attach_favicon(result)
        else
          record_failed_attempt
        end
      rescue ActiveRecord::Deadlocked
        raise
      rescue *TRANSIENT_ERRORS => error
        log_error("Transient error", error)
        raise
      rescue StandardError => error
        record_failed_attempt
        log_error("Failed", error)
      end

      private

      attr_reader :source

      def within_cooldown?
        last_attempt = source.metadata&.dig("favicon_last_attempted_at")
        return false if last_attempt.blank?

        cooldown_days = SourceMonitor.config.favicons.retry_cooldown_days
        Time.parse(last_attempt) > cooldown_days.days.ago
      rescue ArgumentError, TypeError
        false
      end

      def attach_favicon(result)
        blob = ActiveStorage::Blob.create_and_upload!(
          io: result.io,
          filename: result.filename,
          content_type: result.content_type
        )
        source.favicon.attach(blob)
      end

      def record_failed_attempt
        metadata = (source.metadata || {}).merge(
          "favicon_last_attempted_at" => Time.current.iso8601
        )
        source.update_column(:metadata, metadata)
      rescue StandardError
        nil
      end

      def log_error(prefix, error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn(
          "[SourceMonitor::Favicons::Fetcher] #{prefix} for source #{source&.id}: #{error.class} - #{error.message}"
        )
      rescue StandardError
        nil
      end
    end
  end
end
