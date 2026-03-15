# frozen_string_literal: true

require "application_system_test_case"
require "securerandom"
require "nokogiri"

module SourceMonitor
  class DashboardTest < ApplicationSystemTestCase
    def setup
      super
      purge_solid_queue_tables
      SourceMonitor::Dashboard::TurboBroadcaster.setup!
    end

    def teardown
      purge_solid_queue_tables
      super
    end

    test "dashboard displays stats, job metrics, and quick actions" do
      SourceMonitor.configure do |config|
        config.mission_control_enabled = true
        config.mission_control_dashboard_path = -> { SourceMonitor::Engine.routes.url_helpers.root_path }
      end

      source = Source.create!(name: "Example", feed_url: "https://example.com/feed", next_fetch_at: 1.hour.from_now)
      item = Item.create!(source:, guid: "item-1", title: "Dashboard Item", url: "https://example.com/item")
      fetch_log = FetchLog.create!(source:, success: true, items_created: 1, items_updated: 0, started_at: Time.current)
      scrape_log = ScrapeLog.create!(source:, item:, success: false, scraper_adapter: "readability", started_at: 5.minutes.ago)

      seed_queue_activity

      visit source_monitor.root_path

      assert_text "Overview"
      assert_text "Recent Activity"
      assert_text "Upcoming Fetch Schedule"
      assert_text "Quick Actions"
      assert_text "Job Queues"

      within "#source_monitor_dashboard_stats" do
        sources_card = find(:xpath, ".//div[./dt[text()='Sources']]")
        within sources_card do
          assert_text "1"
        end
      end

      assert_selector "span", text: "Success"
      assert_selector "span", text: "Failure"
      assert_selector "a", text: "Go", count: 3
      within "#source_monitor_dashboard_recent_activity" do
        assert_selector "a", text: "Dashboard Item"
        assert_selector "a", text: "Fetch ##{fetch_log.id}"
        assert_selector "a", text: "Scrape ##{scrape_log.id}"
      end

      within "#source_monitor_dashboard_fetch_schedule" do
        assert_text "Upcoming Fetch Schedule"
        assert_text "Example"
      end

      adapter_label = SourceMonitor::Jobs::Visibility.adapter_name.to_s
      assert_text adapter_label
      assert_text SourceMonitor.queue_name(:fetch)
      assert_text SourceMonitor.queue_name(:scrape)
      assert_text "Ready"
      assert_text "Scheduled"
      assert_text "Failed"
      assert_text "Recurring Tasks"
      assert_text "Total: 3"
      assert_text "Paused"
      assert_text "No jobs queued for this role yet."
      assert_selector "a", text: "Open Mission Control"
    end

    test "dashboard streams new items and fetch completions" do
      source = Source.create!(name: "Streamed Source", feed_url: "https://example.com/feed", next_fetch_at: 1.minute.from_now)

      visit source_monitor.dashboard_path
      connect_turbo_cable_stream_sources
      assert_selector "turbo-cable-stream-source", visible: :all

      initial_item_count = Item.count
      streamable = SourceMonitor::Dashboard::TurboBroadcaster::STREAM_NAME
      item = Item.create!(
        source:,
        guid: "turbo-item-#{SecureRandom.hex(4)}",
        url: "https://example.com/items/#{SecureRandom.hex(4)}",
        title: "Turbo Arrival"
      )

      item_messages = capture_turbo_stream_broadcasts(streamable) do
        SourceMonitor::Dashboard::TurboBroadcaster.broadcast_dashboard_updates
      end
      assert item_messages.any?, "expected turbo broadcasts for dashboard updates"
      apply_turbo_stream_messages(item_messages)

      within "#source_monitor_dashboard_stats" do
        assert_selector :xpath,
          ".//dt[text()='Items']/following-sibling::dd[1]",
          text: (initial_item_count + 1).to_s
      end

      within "#source_monitor_dashboard_recent_activity" do
        assert_text "Turbo Arrival"
        assert_text "ITEM"
      end

      fetch_log = FetchLog.create!(
        source:,
        success: true,
        items_created: 1,
        items_updated: 0,
        started_at: Time.current
      )

      fetch_messages = capture_turbo_stream_broadcasts(streamable) do
        SourceMonitor::Dashboard::TurboBroadcaster.broadcast_dashboard_updates
      end
      assert fetch_messages.any?, "expected turbo broadcasts for dashboard updates"
      apply_turbo_stream_messages(fetch_messages)

      within "#source_monitor_dashboard_recent_activity" do
        assert_text "Fetch ##{fetch_log.id}"
      end

      within "#source_monitor_dashboard_fetch_schedule" do
        assert_text "Upcoming Fetch Schedule"
      end
    end
  end
end
