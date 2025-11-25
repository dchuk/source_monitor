# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    class HealthCheckBroadcaster
      include ActionView::RecordIdentifier

      require "source_monitor/import_sessions/entry_normalizer"

      def initialize(import_session)
        @import_session = import_session
      end

      def stream_name
        import_session.health_stream_name
      end

      def broadcast_row(entry)
        return unless turbo_available?
        return unless entry

        Turbo::StreamsChannel.broadcast_replace_to(
          stream_name,
          target: row_target(entry),
          html: render_row(entry)
        )
      end

      def broadcast_progress
        return unless turbo_available?

        Turbo::StreamsChannel.broadcast_replace_to(
          stream_name,
          target: progress_target,
          html: render_progress
        )
      end

      def progress_data
        entries = health_entries
        total = import_session.health_check_targets.size
        completed = entries.count { |entry| %w[healthy unhealthy].include?(entry[:health_status].to_s) }

        {
          completed: completed,
          total: total,
          pending: [ total - completed, 0 ].max,
          active: import_session.health_checks_active?,
          done: total.positive? && completed >= total
        }
      end

      private

      attr_reader :import_session

      def row_target(entry)
        "import_session_#{import_session.id}_health_row_#{entry_id(entry)}"
      end

      def progress_target
        "import_session_#{import_session.id}_health_progress"
      end

      def entry_id(entry)
        entry[:id] || entry["id"]
      end

      def render_row(entry)
        SourceMonitor::ImportSessionsController.render(
          partial: "source_monitor/import_sessions/health_check/row",
          locals: { import_session:, entry: entry_with_selection(entry) }
        )
      end

      def render_progress
        SourceMonitor::ImportSessionsController.render(
          partial: "source_monitor/import_sessions/health_check/progress",
          locals: { import_session:, progress: progress_data }
        )
      end

      def entry_with_selection(entry)
        selected_ids = Array(import_session.selected_source_ids).map(&:to_s)
        normalized = entry.is_a?(Hash) ? entry.symbolize_keys : entry
        normalized.merge(selected: selected_ids.include?(entry_id(entry).to_s))
      end

      def health_entries
        targets = import_session.health_check_targets
        selected_ids = Array(import_session.selected_source_ids).map(&:to_s)

        Array(import_session.parsed_sources).map { |entry| SourceMonitor::ImportSessions::EntryNormalizer.normalize(entry) }
          .select { |entry| targets.include?(entry[:id]) }
          .map { |entry| entry.merge(selected: selected_ids.include?(entry[:id])) }
      end

      def turbo_available?
        defined?(Turbo::StreamsChannel)
      end
    end
  end
end
