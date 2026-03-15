# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ScrapeLogsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @source = create_source!(name: "ScrapeLogTest Source")
      @item = create_item!(source: @source, title: "Scraped Article")
      @scrape_log = create_scrape_log!(
        item: @item,
        source: @source,
        success: true,
        started_at: 1.hour.ago,
        completed_at: 30.minutes.ago
      )
    end

    test "show returns 200 for existing scrape log" do
      get source_monitor.scrape_log_path(@scrape_log)
      assert_response :success
    end

    test "show renders scrape log details" do
      get source_monitor.scrape_log_path(@scrape_log)
      assert_response :success

      assert_includes response.body, "Scrape Log"
      assert_includes response.body, @source.name
      assert_includes response.body, @item.title
      assert_includes response.body, "Scraper Adapter"
    end

    test "show includes item and source links" do
      get source_monitor.scrape_log_path(@scrape_log)
      assert_response :success

      assert_includes response.body, source_monitor.source_path(@source)
      assert_includes response.body, source_monitor.item_path(@item)
    end

    test "show renders failed scrape log with error details" do
      failed_log = create_scrape_log!(
        item: @item,
        source: @source,
        success: false,
        started_at: 2.hours.ago,
        completed_at: 2.hours.ago,
        error_class: "Faraday::ConnectionFailed",
        error_message: "connection refused"
      )

      get source_monitor.scrape_log_path(failed_log)
      assert_response :success

      assert_includes response.body, "Faraday::ConnectionFailed"
      assert_includes response.body, "connection refused"
    end

    test "show returns 404 for nonexistent log" do
      get source_monitor.scrape_log_path(id: 999_999_999)
      assert_response :not_found
    end
  end
end
