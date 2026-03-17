# frozen_string_literal: true

module SourceMonitor
  class ImportHistoryDismissalsController < ApplicationController
    def create
      user_id = source_monitor_current_user&.id
      # Verify the specified import history belongs to this user (authorization check)
      ImportHistory.where(user_id: user_id).find(params[:import_history_id])
      # Dismiss all undismissed import histories for this user so older ones don't resurface
      ImportHistory.where(user_id: user_id).not_dismissed.update_all(dismissed_at: Time.current)

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
