# frozen_string_literal: true

module SourceMonitor
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception, prepend: true

    before_action :enforce_source_monitor_access_default
    before_action :authenticate_source_monitor_user
    before_action :authorize_source_monitor_access

    helper_method :source_monitor_current_user, :source_monitor_user_signed_in?,
      :source_monitor_flash_toasts
    after_action :append_flash_toasts_to_turbo_stream

    rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

    private

    def record_not_found
      respond_to do |format|
        format.html { render plain: "Record not found", status: :not_found }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("flash",
            partial: "source_monitor/shared/toast",
            locals: { message: "Record not found", level: :error }),
            status: :not_found
        end
        format.json { render json: { error: "Record not found" }, status: :not_found }
      end
    end

    FLASH_LEVELS = {
      notice: :success,
      alert: :error,
      error: :error,
      success: :success,
      warning: :warning
    }.freeze

    # Toast display durations in milliseconds. These values are passed to the
    # Stimulus notification_controller via data-notification-delay-value.
    TOAST_DURATION_DEFAULT = 5000
    TOAST_DURATION_ERROR = 6000

    # Fail-closed guard: when the host app has configured no authentication or
    # authorization handler and has not explicitly opted into open access, deny
    # all engine routes. Configured handlers short-circuit this and decide for
    # themselves (see SourceMonitor::Security::Authentication).
    def enforce_source_monitor_access_default
      return unless SourceMonitor::Security::Authentication.access_denied_by_default?(self)

      source_monitor_access_forbidden
    end

    def source_monitor_access_forbidden
      message = "SourceMonitor access is not configured"
      respond_to do |format|
        format.html { render plain: message, status: :forbidden }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("flash",
            partial: "source_monitor/shared/toast",
            locals: { message: message, level: :error }),
            status: :forbidden
        end
        format.json { render json: { error: message }, status: :forbidden }
      end
    end

    def authenticate_source_monitor_user
      SourceMonitor::Security::Authentication.authenticate!(self)
    end

    def authorize_source_monitor_access
      SourceMonitor::Security::Authentication.authorize!(self)
    end

    def source_monitor_current_user
      SourceMonitor::Security::Authentication.current_user(self)
    end

    def source_monitor_user_signed_in?
      SourceMonitor::Security::Authentication.user_signed_in?(self)
    end

    def toast_delay_for(level)
      level.to_sym == :error ? TOAST_DURATION_ERROR : TOAST_DURATION_DEFAULT
    end

    # Request flashes are delivered response-local, never broadcast over the
    # global ActionCable notification stream. On full-page HTML loads the layout
    # renders the toasts inline (see +source_monitor_flash_toasts+); on
    # turbo_stream responses we append the toasts to the response body so they
    # reach only the requesting tab.
    def source_monitor_flash_toasts
      payloads = flash_toast_payloads
      # Reading via the layout consumes the flash for this request so it does
      # not linger into the next one.
      flash.discard unless payloads.empty?
      payloads
    end

    def append_flash_toasts_to_turbo_stream
      return unless request.format.turbo_stream?
      return if response.redirect?

      payloads = flash_toast_payloads
      return if payloads.empty?

      streams = payloads.map do |payload|
        view_context.turbo_stream.append(
          "source_monitor_notifications",
          partial: "source_monitor/shared/toast",
          locals: {
            message: payload[:message],
            level: payload[:level],
            delay_ms: toast_delay_for(payload[:level])
          }
        )
      end

      response.body = "#{response.body}#{streams.join}"
      flash.discard
    end

    # Builds the list of toast payloads ({ message:, level: }) for the current
    # request's flash. Used by both the inline layout renderer and the
    # turbo_stream after_action so request flashes stay response-local.
    def flash_toast_payloads
      return [] if flash.empty?

      flash.flat_map do |key, message|
        Array(message).filter_map do |msg|
          next if msg.blank?

          { message: msg, level: FLASH_LEVELS[key.to_sym] || :info }
        end
      end
    end
  end
end
