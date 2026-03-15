# frozen_string_literal: true

module SourceMonitor
  class ImportOpmlJob < ApplicationJob
    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    def perform(import_session_id, import_history_id)
      import_session = SourceMonitor::ImportSession.find_by(id: import_session_id)
      import_history = SourceMonitor::ImportHistory.find_by(id: import_history_id)
      return unless import_session && import_history

      SourceMonitor::ImportSessions::OPMLImporter.new(
        import_session: import_session,
        import_history: import_history
      ).call
    end
  end
end
