# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class EngineMountingTest < ActionDispatch::IntegrationTest
    test "host app routes mount the engine at /source_monitor" do
      helpers = Rails.application.routes.url_helpers
      assert_respond_to helpers, :source_monitor_path
      assert_equal "/source_monitor", helpers.source_monitor_path
    end

    test "engine root responds with welcome content" do
      get "/source_monitor"
      assert_response :success
      assert_match "SourceMonitor", response.body
    end
  end
end
