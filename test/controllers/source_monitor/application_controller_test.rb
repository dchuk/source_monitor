# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ApplicationControllerTest < ActionDispatch::IntegrationTest
    test "invokes host configured authentication callbacks" do
      calls = []

      SourceMonitor.configure do |config|
        config.authentication.authenticate_with do |controller|
          calls << [ :authenticate, controller.class.name ]
        end

        config.authentication.authorize_with do |controller|
          calls << [ :authorize, controller.class.name ]
        end
      end

      get "/source_monitor/dashboard"

      assert_response :success
      assert_includes calls, [ :authenticate, "SourceMonitor::DashboardController" ]
      assert_includes calls, [ :authorize, "SourceMonitor::DashboardController" ]
      assert_equal [ :authenticate, "SourceMonitor::DashboardController" ], calls.first
    end

    test "skips authentication when host has not configured it" do
      get "/source_monitor/dashboard"

      assert_response :success
    end

    test "uses exception strategy for CSRF protection" do
      assert_equal ActionController::RequestForgeryProtection::ProtectionMethods::Exception,
        SourceMonitor::ApplicationController.forgery_protection_strategy
    end

    test "toast_delay_for returns appropriate delays based on level" do
      controller = SourceMonitor::ApplicationController.new

      assert_equal 5000, controller.send(:toast_delay_for, :info)
      assert_equal 5000, controller.send(:toast_delay_for, :success)
      assert_equal 5000, controller.send(:toast_delay_for, :warning)
      assert_equal 6000, controller.send(:toast_delay_for, :error)
    end

    test "toast_delay_for returns default for unknown level" do
      controller = SourceMonitor::ApplicationController.new

      assert_equal 5000, controller.send(:toast_delay_for, :unknown)
    end

    test "rescue_from RecordNotFound returns 404 for HTML requests" do
      get "/source_monitor/sources/999999999"

      assert_response :not_found
      assert_equal "Record not found", response.body
    end

    test "rescue_from RecordNotFound returns 404 with toast for turbo_stream requests" do
      get "/source_monitor/sources/999999999", as: :turbo_stream

      assert_response :not_found
      assert_includes response.body, "Record not found"
      assert_includes response.body, "turbo-stream"
    end

    test "rescue_from RecordNotFound returns 404 JSON for JSON requests" do
      get "/source_monitor/sources/999999999", as: :json

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Record not found", json["error"]
    end
  end
end
