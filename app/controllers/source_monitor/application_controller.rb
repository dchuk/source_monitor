# frozen_string_literal: true

module SourceMonitor
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception, prepend: true

    before_action :authenticate_source_monitor_user
    before_action :authorize_source_monitor_access

    helper_method :source_monitor_current_user, :source_monitor_user_signed_in?
    after_action :broadcast_flash_toasts

    private

    FLASH_LEVELS = {
      notice: :success,
      alert: :error,
      error: :error,
      success: :success,
      warning: :warning
    }.freeze

    TOAST_DURATION_DEFAULT = 5000
    TOAST_DURATION_ERROR = 6000

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

    def broadcast_flash_toasts
      return if flash.empty?
      return unless request.format.html? || request.format.turbo_stream?

      flash.each do |key, message|
        next if message.blank?

        Array(message).each do |msg|
          SourceMonitor::Realtime.broadcast_toast(
            message: msg,
            level: FLASH_LEVELS[key.to_sym] || :info
          )
        end
      end
    ensure
      flash.discard
    end
  end
end
