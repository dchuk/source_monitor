# frozen_string_literal: true

module SourceMonitor
  class ImportSessionsController < ApplicationController
    before_action :ensure_current_user!
    before_action :set_import_session, only: %i[show update destroy]
    before_action :set_wizard_step, only: %i[show update]

    def new
      import_session = ImportSession.create!(
        user_id: current_user_id,
        current_step: ImportSession.default_step
      )

      redirect_to source_monitor.step_import_session_path(import_session, step: import_session.current_step)
    end

    def create
      import_session = ImportSession.create!(
        user_id: current_user_id,
        current_step: ImportSession.default_step
      )

      redirect_to source_monitor.step_import_session_path(import_session, step: import_session.current_step)
    end

    def show
      persist_step!
      render :show
    end

    def update
      @import_session.update!(session_attributes)
      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def destroy
      @import_session.destroy
      redirect_to source_monitor.sources_path, notice: "Import canceled"
    end

    private

    def set_import_session
      @import_session = ImportSession.find(params[:id])
    end

    def set_wizard_step
      @wizard_steps = ImportSession::STEP_ORDER
      @current_step = permitted_step(params[:step]) || @import_session.current_step || ImportSession.default_step
    end

    def persist_step!
      return if @import_session.current_step == @current_step

      @import_session.update_column(:current_step, @current_step)
    end

    def session_attributes
      attrs = state_params.except(:next_step, :current_step, "next_step", "current_step")
      attrs[:opml_file_metadata] = build_file_metadata if uploading_file?
      attrs[:current_step] = target_step
      attrs
    end

    def state_params
      @state_params ||= begin
        permitted = params.fetch(:import_session, {}).permit(
          :current_step,
          :next_step,
          parsed_sources: [],
          selected_source_ids: [],
          bulk_settings: {},
          opml_file_metadata: {}
        )

        SourceMonitor::Security::ParameterSanitizer.sanitize(permitted.to_h)
      end
    end

    def build_file_metadata
      return {} unless params[:opml_file].respond_to?(:original_filename)

      file = params[:opml_file]
      {
        filename: file.original_filename,
        byte_size: file.size,
        content_type: file.content_type
      }
    end

    def uploading_file?
      params[:opml_file].present?
    end

    def permitted_step(value)
      step = value.to_s.presence
      return unless step

      ImportSession::STEP_ORDER.find { |candidate| candidate == step }
    end

    def target_step
      next_step = state_params[:next_step] || state_params["next_step"]
      permitted_step(next_step) || @current_step || ImportSession.default_step
    end

    def current_user_id
      source_monitor_current_user&.id
    end

    def ensure_current_user!
      head :forbidden unless current_user_id
    end
  end
end
