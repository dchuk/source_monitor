# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FetchLogsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @source = create_source!(name: "FetchLogTest Source")
      @fetch_log = create_fetch_log!(
        source: @source,
        success: true,
        started_at: 1.hour.ago,
        completed_at: 30.minutes.ago,
        items_created: 3,
        items_updated: 1,
        items_failed: 0
      )
    end

    test "show returns 200 for existing fetch log" do
      get source_monitor.fetch_log_path(@fetch_log)
      assert_response :success
    end

    test "show renders fetch log details" do
      get source_monitor.fetch_log_path(@fetch_log)
      assert_response :success

      assert_includes response.body, "Fetch Log"
      assert_includes response.body, @source.name
      assert_includes response.body, "Items Created"
    end

    test "show includes source link" do
      get source_monitor.fetch_log_path(@fetch_log)
      assert_response :success

      assert_includes response.body, source_monitor.source_path(@source)
    end

    test "show renders failed fetch log with error details" do
      failed_log = create_fetch_log!(
        source: @source,
        success: false,
        started_at: 2.hours.ago,
        completed_at: 2.hours.ago,
        error_class: "Faraday::TimeoutError",
        error_message: "execution expired"
      )

      get source_monitor.fetch_log_path(failed_log)
      assert_response :success

      assert_includes response.body, "Faraday::TimeoutError"
      assert_includes response.body, "execution expired"
    end

    test "show returns 404 for nonexistent log" do
      get source_monitor.fetch_log_path(id: 999_999_999)
      assert_response :not_found
    end
  end
end
