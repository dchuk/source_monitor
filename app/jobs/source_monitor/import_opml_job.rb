# frozen_string_literal: true

require "set"
require "source_monitor/import_sessions/entry_normalizer"
require "source_monitor/realtime/broadcaster"
require "source_monitor/sources/params"

module SourceMonitor
  class ImportOpmlJob < ApplicationJob
    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    def perform(import_session_id, import_history_id)
      @import_session = SourceMonitor::ImportSession.find_by(id: import_session_id)
      @import_history = SourceMonitor::ImportHistory.find_by(id: import_history_id)
      return unless import_session && import_history

      import_history.update_columns(started_at: Time.current) unless import_history.started_at

      processed = Set.new

      selected_entries.each do |entry|
        process_entry(entry, processed)
      end

      import_history.update!(
        imported_sources: imported_sources,
        failed_sources: failed_sources,
        skipped_duplicates: skipped_duplicates,
        bulk_settings: import_session.bulk_settings.presence || {},
        completed_at: Time.current
      )

      broadcast_completion(import_history)
    end

    private

    attr_reader :import_session, :import_history

    def selected_entries
      ids = Array(import_session.selected_source_ids).map(&:to_s)

      Array(import_session.parsed_sources)
        .map { |entry| SourceMonitor::ImportSessions::EntryNormalizer.normalize(entry) }
        .select { |entry| ids.include?(entry[:id]) }
    end

    def process_entry(entry, processed)
      feed_url = entry[:feed_url].to_s

      if feed_url.blank?
        failed_sources << failure_payload(feed_url, "MissingFeedURL", "Feed URL is missing")
        return
      end

      normalized_url = feed_url.downcase

      if processed.include?(normalized_url)
        skipped_duplicates << skipped_payload(feed_url, "duplicate in import selection")
        return
      end

      if duplicate_source?(normalized_url)
        skipped_duplicates << skipped_payload(feed_url, "already exists")
        processed << normalized_url
        return
      end

      source = SourceMonitor::Source.new(build_attributes(entry))

      if source.save
        imported_sources << { id: source.id, feed_url: source.feed_url, name: source.name }
        SourceMonitor::FaviconFetchJob.perform_later(source.id) if should_fetch_favicon?(source)
        processed << normalized_url
      else
        failed_sources << failure_payload(feed_url, "ValidationFailed", source.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_duplicates << skipped_payload(feed_url, "already exists")
      processed << normalized_url
    rescue StandardError => error
      failed_sources << failure_payload(feed_url, error.class.name, error.message)
    end

    def duplicate_source?(normalized_feed_url)
      SourceMonitor::Source.where("LOWER(feed_url) = ?", normalized_feed_url).exists?
    end

    def build_attributes(entry)
      defaults = SourceMonitor::Sources::Params.default_attributes.deep_dup
      settings = SourceMonitor::Security::ParameterSanitizer.sanitize(import_session.bulk_settings.presence || {})
      settings = settings.deep_symbolize_keys

      defaults.merge(settings).merge(identity_attributes(entry))
    end

    def identity_attributes(entry)
      {
        name: entry[:title].presence || entry[:feed_url],
        feed_url: entry[:feed_url],
        website_url: entry[:website_url]
      }
    end

    def imported_sources
      @imported_sources ||= []
    end

    def failed_sources
      @failed_sources ||= []
    end

    def skipped_duplicates
      @skipped_duplicates ||= []
    end

    def failure_payload(feed_url, error_class, message)
      {
        feed_url: feed_url,
        error_class: error_class,
        error_message: message
      }
    end

    def skipped_payload(feed_url, reason)
      {
        feed_url: feed_url,
        reason: reason
      }
    end

    def should_fetch_favicon?(source)
      defined?(ActiveStorage) &&
        SourceMonitor.config.favicons.enabled? &&
        source.website_url.present?
    rescue StandardError
      false
    end

    def broadcast_completion(history)
      return unless defined?(Turbo::StreamsChannel)

      histories = SourceMonitor::ImportHistory.recent_for(history.user_id).limit(5)

      Turbo::StreamsChannel.broadcast_replace_to(
        SourceMonitor::Realtime::Broadcaster::SOURCE_INDEX_STREAM,
        target: "source_monitor_import_history_panel",
        html: SourceMonitor::SourcesController.render(
          partial: "source_monitor/sources/import_history_panel",
          locals: { import_histories: histories }
        )
      )
    rescue StandardError => error
      Rails.logger.error("[SourceMonitor::ImportOpmlJob] broadcast failed: #{error.class}: #{error.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    end
  end
end
