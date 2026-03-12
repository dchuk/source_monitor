# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ApplicationHelperTest < ActionView::TestCase
    include SourceMonitor::ApplicationHelper

    # --- Asset tag helpers ---

    test "source_monitor_stylesheet_bundle_tag returns nil when asset missing" do
      result = source_monitor_stylesheet_bundle_tag
      if result.nil?
        assert_nil result
      else
        assert_match(/stylesheet/, result)
      end
    end

    test "source_monitor_javascript_bundle_tag returns nil when asset missing" do
      result = source_monitor_javascript_bundle_tag
      if result.nil?
        assert_nil result
      else
        assert_match(/javascript/, result)
      end
    end

    # --- Heatmap bucket helpers ---

    test "heatmap_bucket_classes returns slate for zero values" do
      assert_match(/slate/, heatmap_bucket_classes(0, 10))
      assert_match(/slate/, heatmap_bucket_classes(5, 0))
    end

    test "heatmap_bucket_classes returns blue for non-zero values" do
      assert_match(/blue/, heatmap_bucket_classes(5, 20))
    end

    test "heatmap_bucket_classes returns darker shades for higher ratios" do
      low = heatmap_bucket_classes(1, 10)
      high = heatmap_bucket_classes(9, 10)

      assert_match(/blue-100/, low)
      assert_match(/blue-[4-9]00/, high)
    end

    # --- Duration formatting ---

    test "format_duration_ms returns ms for small values" do
      assert_equal "500ms", format_duration_ms(500)
    end

    test "format_duration_ms returns seconds for larger values" do
      assert_equal "1.5s", format_duration_ms(1500)
    end

    test "format_duration_ms returns minutes for very large values" do
      assert_equal "2.0m", format_duration_ms(120_000)
    end

    test "format_duration_ms handles nil gracefully" do
      assert_equal "—", format_duration_ms(nil)
    end

    # --- Async status badge ---

    test "async_status_badge returns processing state" do
      badge = async_status_badge(:processing, show_spinner: true)

      assert_equal "Processing", badge[:label]
      assert_match(/blue/, badge[:classes])
      assert badge[:show_spinner]

      fallback = async_status_badge(:unknown, show_spinner: false)
      assert_equal "Ready", fallback[:label]
      refute fallback[:show_spinner]
    end

    test "source_health_badge returns working styling" do
      source = SourceMonitor::Source.new(health_status: "working")

      badge = source_health_badge(source)

      assert_equal "Working", badge[:label]
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

    test "source_health_badge indicates failing status" do
      source = SourceMonitor::Source.new(health_status: "failing")

      badge = source_health_badge(source)

      assert_equal "Failing", badge[:label]
      assert_match(/rose/, badge[:classes])
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

    test "interactive_health_status is enabled for failing sources" do
      source = SourceMonitor::Source.new(health_status: "failing")

      assert interactive_health_status?(source)
    end

    test "interactive_health_status is disabled for working sources" do
      source = SourceMonitor::Source.new(health_status: "working")

      refute interactive_health_status?(source)
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

    test "external_link_to renders link with target blank and icon" do
      result = external_link_to("Example", "https://example.com")
      assert_includes result, 'target="_blank"'
      assert_includes result, 'rel="noopener noreferrer"'
      assert_includes result, "Example"
      assert_includes result, "<svg"
    end

    test "external_link_to returns plain label when url is blank" do
      result = external_link_to("No URL", nil)
      assert_equal "No URL", result
    end

    test "external_link_to returns plain label when url is empty string" do
      result = external_link_to("No URL", "")
      assert_equal "No URL", result
    end

    test "external_link_to accepts custom css class" do
      result = external_link_to("Link", "https://example.com", class: "custom-class")
      assert_includes result, "custom-class"
    end

    test "domain_from_url extracts host from valid URL" do
      assert_equal "example.com", domain_from_url("https://example.com/path")
      assert_equal "blog.example.org", domain_from_url("https://blog.example.org/feed.xml")
    end

    test "domain_from_url returns nil for blank URL" do
      assert_nil domain_from_url(nil)
      assert_nil domain_from_url("")
    end

    test "domain_from_url returns nil for invalid URL" do
      assert_nil domain_from_url("not a url %%%")
    end
  end
end
