# frozen_string_literal: true

require "source_monitor/health/import_source_health_check"
require "source_monitor/import_sessions/entry_normalizer"
require "source_monitor/import_sessions/health_check_broadcaster"

module SourceMonitor
  module ImportSessions
    # Performs a health check for a single OPML import entry: probes the feed
    # URL, acquires a row lock to merge the result into the import session,
    # and broadcasts UI updates. Extracted from ImportSessionHealthCheckJob.
    class HealthCheckUpdater
      def initialize(import_session:, entry_id:)
        @import_session = import_session
        @entry_id = entry_id
      end

      def call
        return unless active_for?(import_session)

        result = perform_health_check
        return unless result

        updated_entry = nil

        import_session.with_lock do
          import_session.reload
          return unless active_for?(import_session)

          entries = Array(import_session.parsed_sources).map(&:to_h)
          index = entries.index { |candidate| entry_id_for(candidate) == entry_id.to_s }
          return unless index

          entries[index] = entries[index].merge(
            "health_status" => result.status,
            "health_error" => result.error_message
          )

          selected_ids = Array(import_session.selected_source_ids).map(&:to_s)
          selected_ids -= [ entry_id.to_s ] if result.status == "failing"

          attrs = {
            parsed_sources: entries,
            selected_source_ids: selected_ids,
            health_check_completed_at: completion_time(entries, import_session.health_check_targets)
          }.compact

          import_session.update!(attrs)
          normalized_entry = SourceMonitor::ImportSessions::EntryNormalizer.normalize(entries[index])
          updated_entry = normalized_entry.merge(selected: selected_ids.include?(entry_id.to_s))
        end

        broadcaster = SourceMonitor::ImportSessions::HealthCheckBroadcaster.new(import_session)
        broadcaster.broadcast_row(updated_entry) if updated_entry
        broadcaster.broadcast_progress
      end

      private

      attr_reader :import_session, :entry_id

      def active_for?(session)
        session.current_step == "health_check" && session.health_checks_active?
      end

      def perform_health_check
        entry = find_entry
        return unless entry

        SourceMonitor::Health::ImportSourceHealthCheck.new(feed_url: entry_feed_url(entry)).call
      end

      def find_entry
        Array(import_session.parsed_sources).find { |entry| entry_id_for(entry) == entry_id.to_s }
      end

      def entry_id_for(entry)
        entry.to_h["id"].presence || entry.to_h[:id].presence || entry.to_h["feed_url"].to_s
      end

      def entry_feed_url(entry)
        entry.to_h["feed_url"] || entry.to_h[:feed_url]
      end

      def completion_time(entries, targets)
        normalized = Array(entries).map { |entry| SourceMonitor::ImportSessions::EntryNormalizer.normalize(entry) }
        filtered = normalized.select { |entry| targets.include?(entry[:id]) }
        return nil if filtered.empty?

        completed = filtered.count { |entry| %w[working failing].include?(entry[:health_status].to_s) }
        completed >= filtered.size ? Time.current : nil
      end
    end
  end
end
