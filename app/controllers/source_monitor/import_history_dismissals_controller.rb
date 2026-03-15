# frozen_string_literal: true

module SourceMonitor
  class ImportHistoryDismissalsController < ApplicationController
    def create
      import_history = ImportHistory.where(user_id: source_monitor_current_user&.id).find(params[:import_history_id])
      import_history.update!(dismissed_at: Time.current)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.remove("source_monitor_import_history_panel")
        end

        format.html do
          redirect_to source_monitor.sources_path, notice: "Import dismissed"
        end
      end
    end
  end
end
