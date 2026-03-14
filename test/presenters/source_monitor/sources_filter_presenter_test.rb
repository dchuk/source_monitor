# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourcesFilterPresenterTest < ActiveSupport::TestCase
    test "has_any_filter? returns false when no filters active" do
      presenter = build_presenter(search_params: {}, search_term: "", fetch_interval_filter: nil)
      assert_not presenter.has_any_filter?
    end

    test "has_any_filter? returns true when search term present" do
      presenter = build_presenter(search_params: {}, search_term: "rails", fetch_interval_filter: nil)
      assert presenter.has_any_filter?
    end

    test "has_any_filter? returns true when dropdown filter active" do
      presenter = build_presenter(
        search_params: { "active_eq" => "true" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert presenter.has_any_filter?
    end

    test "has_any_filter? returns true when fetch interval filter present" do
      presenter = build_presenter(
        search_params: {},
        search_term: "",
        fetch_interval_filter: { min: 10, max: 60 }
      )
      assert presenter.has_any_filter?
    end

    test "active_filter_keys returns only keys with present values" do
      presenter = build_presenter(
        search_params: { "active_eq" => "true", "health_status_eq" => "", "feed_format_eq" => "rss" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert_equal %w[active_eq feed_format_eq], presenter.active_filter_keys.sort
    end

    test "active_filter_keys returns empty array when no dropdown filters" do
      presenter = build_presenter(search_params: {}, search_term: "test", fetch_interval_filter: nil)
      assert_equal [], presenter.active_filter_keys
    end

    test "filter_labels returns hash with humanized labels for active filters" do
      presenter = build_presenter(
        search_params: { "active_eq" => "true", "feed_format_eq" => "rss" },
        search_term: "",
        fetch_interval_filter: nil
      )
      labels = presenter.filter_labels
      assert_equal "Status: Active", labels["active_eq"]
      assert_equal "Format: RSS", labels["feed_format_eq"]
    end

    test "filter_labels handles status paused" do
      presenter = build_presenter(
        search_params: { "active_eq" => "false" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert_equal "Status: Paused", presenter.filter_labels["active_eq"]
    end

    test "filter_labels handles scraping enabled/disabled" do
      enabled = build_presenter(
        search_params: { "scraping_enabled_eq" => "true" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert_equal "Scraping: Enabled", enabled.filter_labels["scraping_enabled_eq"]

      disabled = build_presenter(
        search_params: { "scraping_enabled_eq" => "false" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert_equal "Scraping: Disabled", disabled.filter_labels["scraping_enabled_eq"]
    end

    test "filter_labels includes avg_feed_words_lt" do
      presenter = build_presenter(
        search_params: { "avg_feed_words_lt" => "500" },
        search_term: "",
        fetch_interval_filter: nil
      )
      assert_equal "Avg Feed Words: < 500", presenter.filter_labels["avg_feed_words_lt"]
    end

    test "adapter_options returns provided adapter list" do
      presenter = build_presenter(
        search_params: {},
        search_term: "",
        fetch_interval_filter: nil,
        adapter_options: %w[readability custom]
      )
      assert_equal %w[readability custom], presenter.adapter_options
    end

    private

    def build_presenter(search_params:, search_term:, fetch_interval_filter:, adapter_options: [])
      SourceMonitor::SourcesFilterPresenter.new(
        search_params: search_params,
        search_term: search_term,
        fetch_interval_filter: fetch_interval_filter,
        adapter_options: adapter_options
      )
    end
  end
end
