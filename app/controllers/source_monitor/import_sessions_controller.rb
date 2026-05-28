# frozen_string_literal: true

require "nokogiri"
require "uri"
require "source_monitor/import_sessions/entry_normalizer"
require "source_monitor/import_sessions/wizard"
require "source_monitor/sources/params"

module SourceMonitor
  class ImportSessionsController < ApplicationController
    include SourceMonitor::ImportSessions::OpmlParser
    include SourceMonitor::ImportSessions::EntryAnnotation
    include SourceMonitor::ImportSessions::HealthCheckManagement
    include SourceMonitor::ImportSessions::BulkConfiguration

    STEP_HANDLERS = {
      "upload" => :handle_upload_step,
      "preview" => :handle_preview_step,
      "health_check" => :handle_health_check_step,
      "configure" => :handle_configure_step,
      "confirm" => :handle_confirm_step
    }.freeze

    STEP_CONTEXTS = {
      "preview" => :prepare_preview_context,
      "health_check" => :prepare_health_check_context,
      "configure" => :prepare_configure_context,
      "confirm" => :prepare_confirm_context
    }.freeze

    before_action :ensure_current_user!
    before_action :set_import_session, only: %i[show update destroy]
    before_action :authorize_import_session!, only: %i[show update destroy]
    before_action :set_wizard_step, only: %i[show update]

    # The OPML import wizard requires a persisted ImportSession record to track
    # state across steps (file upload, preview, health check, configure, confirm).
    # Visiting "new" immediately creates a session and redirects to the first step,
    # so there is no separate form -- the wizard IS the form.
    def new
      create
    end

    def create
      import_session = ImportSession.create!(
        user_id: current_user_id,
        current_step: ImportSession.default_step
      )

      redirect_to source_monitor.step_import_session_path(import_session, step: import_session.current_step)
    end

    def show
      context_method = STEP_CONTEXTS[@current_step]
      send(context_method) if context_method
      persist_step!
      render :show
    end

    def update
      handler = STEP_HANDLERS[@current_step]
      return send(handler) if handler

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

      import_session_wizard.deactivate_health_checks if @current_step != "health_check"
      @import_session.update_column(:current_step, @current_step)
    end

    def handle_health_check_step
      result = import_session_wizard.handle_health_check
      @selected_source_ids = result.selected_source_ids

      if result.blocked?
        @selection_error = result.selection_error
        apply_health_check_context(result.health_check_context)
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = result.current_step
      apply_health_check_context(result.health_check_context) if @current_step == "health_check"
      redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step), allow_other_host: false
    end

    def handle_upload_step
      result = import_session_wizard.handle_upload
      @upload_errors = result.errors
      if @upload_errors.any?
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = result.current_step
      apply_preview_context(result.preview_context) if @current_step == "preview"

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def handle_preview_step
      result = import_session_wizard.handle_preview
      @selected_source_ids = result.selected_source_ids

      if result.blocked?
        @selection_error = result.selection_error
        apply_preview_context(result.preview_context)
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = result.current_step

      if @current_step == "health_check"
        prepare_health_check_context
      else
        apply_preview_context(result.preview_context)
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
      result = import_session_wizard.handle_confirm
      apply_confirm_context(result)

      if result.blocked?
        @selection_error = result.selection_error
        render :show, status: :unprocessable_entity
        return
      end

      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(message: result.message, level: :success)
          responder.redirect(source_monitor.sources_path)
          render turbo_stream: responder.render(view_context)
        end

        format.html do
          redirect_to source_monitor.sources_path, notice: result.message
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

      # Only create guest users in development/test. An engine should never
      # create records in host-app tables in production.
      unless Rails.env.local?
        @fallback_user_id = nil
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

    def import_session_wizard
      SourceMonitor::ImportSessions::Wizard.new(
        import_session: @import_session,
        params: params,
        current_step: @current_step
      )
    end

    def prepare_preview_context(skip_default: false)
      apply_preview_context(import_session_wizard.preview_context(skip_default: skip_default))
    end

    def prepare_health_check_context
      apply_health_check_context(import_session_wizard.health_check_context)
    end

    def prepare_confirm_context
      apply_confirm_context(import_session_wizard.confirm_context)
    end

    def apply_preview_context(context)
      @filter = context.filter
      @page = context.page
      @selected_source_ids = context.selected_source_ids
      @preview_entries = context.preview_entries
      @filtered_entries = context.filtered_entries
      @paginated_entries = context.paginated_entries
      @has_next_page = context.has_next_page
      @has_previous_page = context.has_previous_page
    end

    def apply_health_check_context(context)
      @selected_source_ids = context.selected_source_ids
      @health_check_entries = context.health_check_entries
      @health_check_target_ids = context.health_check_target_ids
      @health_progress = context.health_progress
    end

    def apply_confirm_context(context)
      @selected_source_ids = context.selected_source_ids
      @selected_entries = context.selected_entries
      @bulk_settings = context.bulk_settings
    end

    def authorize_import_session!
      return if !SourceMonitor::Security::Authentication.authentication_configured?

      head :forbidden unless @import_session.user_id == current_user_id
    end
  end
end
