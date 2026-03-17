# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "index renders successfully" do
      get "/source_monitor/dashboard"
      assert_response :success
    end

    test "index renders scrape recommendations widget when candidates exist" do
      SourceMonitor.configure do |config|
        config.scraping.scrape_recommendation_threshold = 200
      end

      source = create_source!(name: "Low WC Dash #{SecureRandom.hex(4)}", scraping_enabled: false)
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/dash-#{SecureRandom.hex(4)}",
        content: "short content"
      )
      get "/source_monitor/dashboard"
      assert_response :success
      assert_select "h2", text: "Scrape Recommendations"
      assert_select "a", text: "View Candidates"
    end

    test "index does not render scrape recommendations widget when no candidates" do
      get "/source_monitor/dashboard"
      assert_response :success
      assert_select "h2", text: "Scrape Recommendations", count: 0
    end

    test "index accepts valid schedule_pages params with group keys" do
      get "/source_monitor/dashboard", params: { schedule_pages: { "0-30": "2", "240+": "1" } }
      assert_response :success
    end

    test "index filters out non-group schedule_pages keys" do
      get "/source_monitor/dashboard", params: { schedule_pages: { "0-30": "2", malicious_key: "evil" } }
      assert_response :success
    end

    test "index paginates fetch schedule groups" do
      sources = 12.times.map do |i|
        create_source!(
          name: "Paginated Source #{i} #{SecureRandom.hex(4)}",
          next_fetch_at: (5 + i).minutes.from_now,
          fetch_interval_minutes: 15
        )
      end

      # Page 1 should show first 10 sources
      get "/source_monitor/dashboard"
      assert_response :success
      assert_select "turbo-frame[id='source_monitor_schedule_0-30']" do
        assert_select "a[data-turbo-frame='source_monitor_schedule_0-30']", text: /Next/
      end

      # Page 2 should show remaining sources
      get "/source_monitor/dashboard", params: { schedule_pages: { "0-30": "2" } }
      assert_response :success
      assert_select "turbo-frame[id='source_monitor_schedule_0-30']" do
        assert_select "a[data-turbo-frame='source_monitor_schedule_0-30']", text: /Previous/
      end
    end
  end
end
