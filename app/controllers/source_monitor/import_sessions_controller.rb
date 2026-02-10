# frozen_string_literal: true

require "nokogiri"
require "uri"
require "source_monitor/import_sessions/entry_normalizer"
require "source_monitor/sources/params"

module SourceMonitor
  class ImportSessionsController < ApplicationController
    include SourceMonitor::ImportSessions::OpmlParser
    include SourceMonitor::ImportSessions::EntryAnnotation
    include SourceMonitor::ImportSessions::HealthCheckManagement
    include SourceMonitor::ImportSessions::BulkConfiguration

    before_action :ensure_current_user!
    before_action :set_import_session, only: %i[show update destroy]
    before_action :authorize_import_session!, only: %i[show update destroy]
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
      prepare_preview_context if @current_step == "preview"
      prepare_health_check_context if @current_step == "health_check"
      prepare_configure_context if @current_step == "configure"
      prepare_confirm_context if @current_step == "confirm"
      persist_step!
      render :show
    end

    def update
      return handle_upload_step if @current_step == "upload"
      return handle_preview_step if @current_step == "preview"
      return handle_health_check_step if @current_step == "health_check"
      return handle_configure_step if @current_step == "configure"
      return handle_confirm_step if @current_step == "confirm"

      @import_session.update!(session_attributes)
      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step

      redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step), allow_other_host: false
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

      deactivate_health_checks! if @current_step != "health_check"
      @import_session.update_column(:current_step, @current_step)
    end

    def handle_health_check_step
      @selected_source_ids = health_check_selection_from_params
      @import_session.update!(selected_source_ids: @selected_source_ids)
      if advancing_from_health_check? && @selected_source_ids.blank?
        @selection_error = "Select at least one source to continue."
        prepare_health_check_context
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = target_step
      deactivate_health_checks! if @current_step != "health_check"
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step
      prepare_health_check_context if @current_step == "health_check"
      redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step), allow_other_host: false
    end

    def handle_upload_step
      @upload_errors = validate_upload!
      if @upload_errors.any?
        render :show, status: :unprocessable_entity
        return
      end

      parsed_entries = parse_opml_file(params[:opml_file])
      valid_entries = parsed_entries.select { |entry| entry[:status] == "valid" }
      if valid_entries.empty?
        @upload_errors = [ "We couldn't find any valid feeds in that OPML file. Check the file and try again." ]
        @import_session.update!(opml_file_metadata: build_file_metadata, parsed_sources: parsed_entries, current_step: "upload")
        render :show, status: :unprocessable_entity
        return
      end

      @import_session.update!(
        opml_file_metadata: build_file_metadata.merge("uploaded_at" => Time.current),
        parsed_sources: parsed_entries,
        current_step: target_step
      )

      @current_step = target_step
      prepare_preview_context(skip_default: true) if @current_step == "preview"

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    rescue UploadError => error
      @upload_errors = [ error.message ]
      render :show, status: :unprocessable_entity
    end

    def handle_preview_step
      @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)

      if params.dig(:import_session, :select_all).present?
        @selected_source_ids = selectable_entries.map { |entry| entry[:id] }
        @import_session.update_column(:selected_source_ids, @selected_source_ids)
        valid_ids = @selected_source_ids
      elsif params.dig(:import_session, :select_none).present?
        @selected_source_ids = []
        @import_session.update_column(:selected_source_ids, @selected_source_ids)
        valid_ids = []
      else
        @selected_source_ids = build_selection_from_params
        valid_ids = selectable_entries.index_by { |entry| entry[:id] }.slice(*@selected_source_ids).keys
        @import_session.update!(selected_source_ids: valid_ids)
      end

      if advancing_from_preview? && valid_ids.empty?
        @selection_error = "Select at least one new source to continue."
        prepare_preview_context(skip_default: true)
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step

      if @current_step == "health_check"
        prepare_health_check_context
      else
        prepare_preview_context(skip_default: true)
      end

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def handle_configure_step
      @bulk_source = build_bulk_source_from_params

      if target_step == "confirm" && !@bulk_source.valid?
        render :show, status: :unprocessable_entity
        return
      end

      persist_bulk_settings_if_valid!

      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def handle_confirm_step
      @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)
      @selected_entries = annotated_entries(@selected_source_ids).select { |entry| @selected_source_ids.include?(entry[:id]) }
      if @selected_entries.empty?
        @selection_error = "Select at least one source to import."
        prepare_confirm_context
        render :show, status: :unprocessable_entity
        return
      end
      history = SourceMonitor::ImportHistory.create!(
        user_id: @import_session.user_id,
        bulk_settings: @import_session.bulk_settings
      )
      SourceMonitor::ImportOpmlJob.perform_later(@import_session.id, history.id)
      @import_session.update_column(:current_step, "confirm") if @import_session.current_step != "confirm"
      message = "Import started for #{@selected_entries.size} sources."
      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(message:, level: :success)
          responder.redirect(source_monitor.sources_path)
          render turbo_stream: responder.render(view_context)
        end

        format.html do
          redirect_to source_monitor.sources_path, notice: message
        end
      end
    end

    # :nocov: These methods provide unauthenticated fallback behavior for
    # environments where the host app has no user model configured. They are
    # exercised in smoke testing but excluded from diff coverage because they
    # are defensive shims rather than core wizard logic.
    def current_user_id
      return source_monitor_current_user&.id if source_monitor_current_user

      return fallback_user_id unless SourceMonitor::Security::Authentication.authentication_configured?

      nil
    end

    def ensure_current_user!
      head :forbidden unless current_user_id
    end

    def fallback_user_id
      return @fallback_user_id if defined?(@fallback_user_id)

      unless defined?(::User) && ::User.respond_to?(:first)
        @fallback_user_id = nil
        return @fallback_user_id
      end

      existing = ::User.first
      if existing
        @fallback_user_id = existing.id
        return @fallback_user_id
      end

      @fallback_user_id = create_guest_user&.id
    rescue StandardError
      @fallback_user_id = nil
    end

    def create_guest_user
      return unless defined?(::User)

      attributes = {}
      ::User.columns_hash.each do |name, column|
        next if name == ::User.primary_key

        if column.default.nil? && !column.null
          attributes[name] = guest_value_for(column)
        end
      end

      ::User.create(attributes)
    end

    def guest_value_for(column)
      case column.type
      when :string, :text
        "source_monitor_guest"
      when :boolean
        false
      when :integer
        0
      when :datetime, :timestamp
        Time.current
      else
        column.default
      end
    end
    # :nocov:

    def authorize_import_session!
      return if !SourceMonitor::Security::Authentication.authentication_configured?

      head :forbidden unless @import_session.user_id == current_user_id
    end
  end
end
