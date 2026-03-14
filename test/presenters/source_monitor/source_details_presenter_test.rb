# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceDetailsPresenterTest < ActiveSupport::TestCase
    setup do
      @source = create_source!(
        name: "Presenter Test Source",
        feed_url: "https://example.com/presenter-test.xml",
        website_url: "https://example.com",
        fetch_interval_minutes: 30,
        scraper_adapter: "readability",
        adaptive_fetching_enabled: false,
        feed_content_readability_enabled: true,
        scraping_enabled: true,
        auto_scrape: false,
        requires_javascript: false,
        failure_count: 0,
        fetch_retry_attempt: 0,
        active: true
      )
      @presenter = SourceDetailsPresenter.new(@source)
    end

    # -- Delegation --

    test "delegates name to underlying source" do
      assert_equal "Presenter Test Source", @presenter.name
    end

    test "delegates feed_url to underlying source" do
      assert_equal "https://example.com/presenter-test.xml", @presenter.feed_url
    end

    test "exposes underlying model via #model" do
      assert_equal @source, @presenter.model
    end

    # -- fetch_interval_display --

    test "fetch_interval_display returns formatted string with minutes and hours" do
      result = @presenter.fetch_interval_display
      assert_includes result, "30 minutes"
      assert_includes result, "0.50 hours"
    end

    test "fetch_interval_display with 60 minutes shows 1.00 hours" do
      @source.update_column(:fetch_interval_minutes, 60)
      result = @presenter.fetch_interval_display
      assert_includes result, "60 minutes"
      assert_includes result, "1.00 hours"
    end

    # -- circuit_state_label --

    test "circuit_state_label returns Closed when circuit is not open" do
      assert_equal "Closed", @presenter.circuit_state_label
    end

    test "circuit_state_label returns Open with date when circuit is open" do
      future_time = 2.hours.from_now
      @source.update_columns(fetch_circuit_until: future_time)
      result = @presenter.circuit_state_label
      assert_match(/\AOpen until /, result)
      assert_includes result, future_time.strftime("%b %d, %Y %H:%M")
    end

    # -- adaptive_interval_label --

    test "adaptive_interval_label returns Fixed when disabled" do
      @source.update_column(:adaptive_fetching_enabled, false)
      assert_equal "Fixed", @presenter.adaptive_interval_label
    end

    test "adaptive_interval_label returns Auto when enabled" do
      @source.update_column(:adaptive_fetching_enabled, true)
      assert_equal "Auto", @presenter.adaptive_interval_label
    end

    # -- details_hash --

    test "details_hash returns a Hash" do
      result = @presenter.details_hash
      assert_kind_of Hash, result
    end

    test "details_hash contains expected keys" do
      result = @presenter.details_hash
      expected_keys = [
        "Fetch interval", "Adaptive interval", "Scraper", "Feed content",
        "Active", "Scraping", "Auto scrape", "Requires JS",
        "Failure count", "Retry attempt", "Circuit state",
        "Last error", "Items count", "Retention days", "Max items"
      ]
      expected_keys.each do |key|
        assert result.key?(key), "Expected details_hash to include key '#{key}'"
      end
    end

    test "details_hash does not include Website key" do
      # Website requires view helper (external_link_to), handled in template
      result = @presenter.details_hash
      assert_not result.key?("Website"), "Website should be handled in template, not presenter"
    end

    test "details_hash fetch interval value uses fetch_interval_display" do
      result = @presenter.details_hash
      assert_equal @presenter.fetch_interval_display, result["Fetch interval"]
    end

    test "details_hash scraping shows Enabled when scraping_enabled" do
      @source.update_column(:scraping_enabled, true)
      result = @presenter.details_hash
      assert_equal "Enabled", result["Scraping"]
    end

    test "details_hash scraping shows Disabled when not scraping_enabled" do
      @source.update_column(:scraping_enabled, false)
      result = @presenter.details_hash
      assert_equal "Disabled", result["Scraping"]
    end

    test "details_hash last_error shows None when blank" do
      @source.update_column(:last_error, nil)
      result = @presenter.details_hash
      assert_equal "None", result["Last error"]
    end

    test "details_hash last_error shows error text when present" do
      @source.update_column(:last_error, "Connection timeout")
      result = @presenter.details_hash
      assert_equal "Connection timeout", result["Last error"]
    end

    test "details_hash retention_days shows dash when nil" do
      @source.update_column(:items_retention_days, nil)
      result = @presenter.details_hash
      assert_equal "\u2014", result["Retention days"]
    end

    test "details_hash max_items shows dash when nil" do
      @source.update_column(:max_items, nil)
      result = @presenter.details_hash
      assert_equal "\u2014", result["Max items"]
    end

    # -- formatted_next_fetch_at --

    test "formatted_next_fetch_at returns dash when nil" do
      @source.update_column(:next_fetch_at, nil)
      assert_equal "\u2014", @presenter.formatted_next_fetch_at
    end

    test "formatted_next_fetch_at returns formatted date when present" do
      time = Time.zone.parse("2026-03-14 15:30:00")
      @source.update_column(:next_fetch_at, time)
      result = @presenter.formatted_next_fetch_at
      assert_includes result, "Mar 14, 2026"
      assert_includes result, "15:30"
    end

    # -- formatted_last_fetched_at --

    test "formatted_last_fetched_at returns dash when nil" do
      @source.update_column(:last_fetched_at, nil)
      assert_equal "\u2014", @presenter.formatted_last_fetched_at
    end

    test "formatted_last_fetched_at returns formatted date when present" do
      time = Time.zone.parse("2026-03-14 10:00:00")
      @source.update_column(:last_fetched_at, time)
      result = @presenter.formatted_last_fetched_at
      assert_includes result, "Mar 14, 2026"
      assert_includes result, "10:00"
    end
  end
end
