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

    # Issue #130: request flashes must be delivered response-local and must NOT
    # be broadcast to the global source_monitor_notifications ActionCable stream
    # (which every connected tab subscribes to).
    test "html request flash renders the toast inline in its own response without global broadcast" do
      source = create_source!(scraping_enabled: true)
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/article-#{SecureRandom.hex(4)}",
        title: "Test Article"
      )

      broadcast_calls = []
      SourceMonitor::Realtime.stub(
        :broadcast_toast,
        ->(**kwargs) { broadcast_calls << kwargs }
      ) do
        post source_monitor.item_scrape_path(item)
        assert_redirected_to source_monitor.item_path(item)
        follow_redirect!
      end

      assert_response :success
      # The flash toast is rendered into the page response (response-local).
      assert_includes response.body, "Scrape has been enqueued and will run shortly."
      assert_includes response.body, "data-controller=\"notification\""
      # The request flash was never pushed to the global notification stream.
      assert_empty broadcast_calls,
        "request flashes must not be broadcast to the global notification stream"
    end

    test "turbo_stream request flash is appended response-local without global broadcast" do
      source = create_source!

      broadcast_calls = []
      SourceMonitor::Realtime.stub(
        :broadcast_toast,
        ->(**kwargs) { broadcast_calls << kwargs }
      ) do
        get "/source_monitor/sources/999999999", as: :turbo_stream
      end

      assert_response :not_found
      assert_includes response.body, "Record not found"
      assert_empty broadcast_calls,
        "request flashes must not be broadcast to the global notification stream"
    end
  end
end
