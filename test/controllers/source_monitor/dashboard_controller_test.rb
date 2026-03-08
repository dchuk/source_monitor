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
      SourceMonitor::ItemContent.create!(item: item)

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
  end
end
