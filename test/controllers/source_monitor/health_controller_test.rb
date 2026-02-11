# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class HealthControllerTest < ActionDispatch::IntegrationTest
    setup do
      SourceMonitor::Metrics.reset!
    end

    test "returns ok status with metrics snapshot" do
      SourceMonitor::Instrumentation.fetch_start(source_id: 10)

      get "/source_monitor/health"

      assert_response :success

      body = JSON.parse(response.body)
      assert_equal "ok", body["status"]
      assert_equal 10, body.dig("metrics", "gauges", "last_fetch_source_id")
    end
  end
end
