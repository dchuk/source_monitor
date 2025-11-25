# frozen_string_literal: true

require "test_helper"
require "rack/utils"
require "uri"

module SourceMonitor
  class ApplicationHelperTest < ActionView::TestCase
    include SourceMonitor::ApplicationHelper

    test "source_monitor_stylesheet_bundle_tag renders link tag" do
      tag = source_monitor_stylesheet_bundle_tag

      assert_includes tag, "source_monitor/application"
      assert_includes tag, "rel=\"stylesheet\""
    end

    test "source_monitor_stylesheet_bundle_tag logs and returns nil on error" do
      Rails.stub(:logger, Logger.new(IO::NULL)) do
        stub(:stylesheet_link_tag, ->(*_args) { raise StandardError, "boom" }) do
          assert_nil source_monitor_stylesheet_bundle_tag
        end
      end
    end

    test "source_monitor_javascript_bundle_tag renders module script" do
      tag = source_monitor_javascript_bundle_tag

      assert_includes tag, "source_monitor/application"
      assert_includes tag, "type=\"module\""
    end

    test "source_monitor_javascript_bundle_tag logs and returns nil on error" do
      Rails.stub(:logger, Logger.new(IO::NULL)) do
        stub(:javascript_include_tag, ->(*_args) { raise StandardError, "boom" }) do
          assert_nil source_monitor_javascript_bundle_tag
        end
      end
    end

    test "heatmap_bucket_classes maps ratios to expected classes" do
      assert_equal "bg-slate-100 text-slate-500", heatmap_bucket_classes(0, 10)
      assert_equal "bg-blue-100 text-blue-800", heatmap_bucket_classes(1, 10)
      assert_equal "bg-blue-200 text-blue-900", heatmap_bucket_classes(3, 10)
      assert_equal "bg-blue-400 text-white", heatmap_bucket_classes(6, 10)
      assert_equal "bg-blue-600 text-white", heatmap_bucket_classes(9, 10)
    end

    test "fetch_interval_bucket_query toggles filters for selection" do
      bucket = Struct.new(:min, :max).new(10, 30)
      params = { "fetch_interval_minutes_gteq" => "5", "fetch_interval_minutes_lt" => "15", "status" => "active" }

      query = fetch_interval_bucket_query(bucket, params, selected: false)

      assert_equal({ "status" => "active", "fetch_interval_minutes_gteq" => "10", "fetch_interval_minutes_lt" => "30" }, query)

      deselected = fetch_interval_bucket_query(bucket, params, selected: true)

      assert_equal({ "status" => "active" }, deselected)
    end

    test "fetch_interval_bucket_path builds query string when filters present" do
      bucket = Struct.new(:min, :max).new(15, nil)
      params = { "status" => "paused" }

      path = fetch_interval_bucket_path(bucket, params, selected: false)
      uri = URI.parse(path)
      parsed = Rack::Utils.parse_nested_query(uri.query || path.split("?", 2)[1])

      assert_equal "/source_monitor/sources", uri.path
      assert_equal "paused", parsed.dig("q", "status")
      assert_equal "15", parsed.dig("q", "fetch_interval_minutes_gteq")

      cleared = fetch_interval_bucket_path(bucket, params, selected: true)
      cleared_uri = URI.parse(cleared)
      cleared_params = Rack::Utils.parse_nested_query(cleared_uri.query || cleared.split("?", 2)[1])

      assert_equal "/source_monitor/sources", cleared_uri.path
      assert_equal "paused", cleared_params.dig("q", "status")
      assert_nil cleared_params.dig("q", "fetch_interval_minutes_gteq")
    end

    test "fetch_interval_filter_label falls back to range text" do
      bucket = Struct.new(:label).new("Custom label")
      assert_equal "Custom label", fetch_interval_filter_label(bucket, nil)

      filter = { min: 5, max: 10 }
      assert_equal "5-10 min", fetch_interval_filter_label(nil, filter)

      assert_equal "5+ min", fetch_interval_filter_label(nil, { min: 5 })
    end

    test "fetch_schedule_window_label formats time windows" do
      group = Struct.new(:window_start, :window_end).new(Time.zone.parse("2025-10-21 10:00"), Time.zone.parse("2025-10-21 12:00"))

      label = fetch_schedule_window_label(group)

      assert_match(/10:00/, label)
      assert_match(/12:00/, label)

      start_only = Struct.new(:window_start, :window_end).new(Time.zone.parse("2025-10-21 15:00"), nil)

      assert_match(/15:00/, fetch_schedule_window_label(start_only))
    end

    test "human_fetch_interval renders hours and minutes" do
      assert_equal "—", human_fetch_interval(nil)
      assert_equal "30m", human_fetch_interval(30)
      assert_equal "2h 5m", human_fetch_interval(125)
    end

    test "async_status_badge normalizes status details" do
      badge = async_status_badge(:fetching)

      assert_equal "Processing", badge[:label]
      assert_match(/blue/, badge[:classes])
      assert badge[:show_spinner]

      fallback = async_status_badge(:unknown, show_spinner: false)
      assert_equal "Ready", fallback[:label]
      refute fallback[:show_spinner]
    end

    test "source_health_badge returns healthy styling" do
      source = SourceMonitor::Source.new(health_status: "healthy")

      badge = source_health_badge(source)

      assert_equal "Healthy", badge[:label]
      assert_match(/green/, badge[:classes])
    end

    test "source_health_badge highlights declining status" do
      source = SourceMonitor::Source.new(health_status: "declining")

      badge = source_health_badge(source)

      assert_equal "Declining", badge[:label]
      assert_match(/orange/, badge[:classes])
    end

    test "source_health_badge highlights improving status" do
      source = SourceMonitor::Source.new(health_status: "improving")

      badge = source_health_badge(source)

      assert_equal "Improving", badge[:label]
      assert_match(/sky|blue|green/, badge[:classes])
    end

    test "source_health_badge indicates auto paused" do
      source = SourceMonitor::Source.new(health_status: "auto_paused")

      badge = source_health_badge(source)

      assert_equal "Auto-Paused", badge[:label]
      assert_match(/amber|rose/, badge[:classes])
    end

    test "source_health_actions include recovery options for declining sources" do
      source = SourceMonitor::Source.new(
        id: 42,
        health_status: "declining"
      )

      actions = source_health_actions(source)
      keys = actions.map { |action| action[:key] }

      assert_equal %i[full_fetch health_check], keys
      assert actions.all? { |action| action[:data][:testid].present? }
    end

    test "interactive_health_status is enabled for declining sources" do
      source = SourceMonitor::Source.new(health_status: "declining")

      assert interactive_health_status?(source)
    end

    test "item_scrape_status_badge shows scraped label for success" do
      source = SourceMonitor::Source.new(scraping_enabled: true)
      item = SourceMonitor::Item.new(source:, guid: "status-success", url: "https://example.com/success", scrape_status: "success")

      badge = item_scrape_status_badge(item: item)

      assert_equal "success", badge[:status]
      assert_equal "Scraped", badge[:label]
      refute badge[:show_spinner]
      assert_match(/green/, badge[:classes])
    end

    test "item_scrape_status_badge shows pending spinner" do
      source = SourceMonitor::Source.new(scraping_enabled: true)
      item = SourceMonitor::Item.new(source:, guid: "status-pending", url: "https://example.com/pending", scrape_status: "pending")

      badge = item_scrape_status_badge(item: item)

      assert_equal "pending", badge[:status]
      assert_equal "Pending", badge[:label]
      assert badge[:show_spinner]
      assert_match(/amber|blue/, badge[:classes])
    end

    test "formatted_setting_value renders friendly values" do
      assert_equal "Enabled", formatted_setting_value(true)
      assert_equal "Disabled", formatted_setting_value(false)
      assert_equal "—", formatted_setting_value(nil)
      assert_equal "a, b", formatted_setting_value(%w[a b])

      hash_value = formatted_setting_value({ timeout: 5 })
      assert_includes hash_value, "timeout"
      assert_includes hash_value, "5"

      assert_equal "plain", formatted_setting_value("plain")
    end

    test "item_scrape_status_badge reports disabled when source scraping disabled" do
      source = SourceMonitor::Source.new(scraping_enabled: false)
      item = SourceMonitor::Item.new(source:, guid: "status-disabled", url: "https://example.com/disabled")

      badge = item_scrape_status_badge(item: item, source: source)

      assert_equal "disabled", badge[:status]
      assert_equal "Disabled", badge[:label]
      refute badge[:show_spinner]
      assert_match(/slate/, badge[:classes])
    end

    test "item_scrape_status_badge treats never scraped items as not scraped" do
      source = SourceMonitor::Source.new(scraping_enabled: true)
      item = SourceMonitor::Item.new(source:, guid: "status-never", url: "https://example.com/never")

      badge = item_scrape_status_badge(item: item, source: source)

      assert_equal "idle", badge[:status]
      assert_equal "Not scraped", badge[:label]
      refute badge[:show_spinner]
      assert_match(/slate/, badge[:classes])
    end
  end
end
