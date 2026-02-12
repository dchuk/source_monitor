# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class RecentActivityPresenterTest < ActiveSupport::TestCase
      test "builds fetch event view model with path" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :fetch_log,
          id: 42,
          occurred_at: Time.current,
          success: true,
          items_created: 3,
          items_updated: 1
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_equal "Fetch #42", result[:label]
        assert_equal :success, result[:status]
        assert_equal SourceMonitor::Engine.routes.url_helpers.fetch_log_path(42), result[:path]
      end

      test "builds item event view model with fallbacks" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :item,
          id: 7,
          occurred_at: Time.current,
          success: true,
          item_title: nil,
          item_url: "https://example.com/items/7",
          source_name: nil
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_equal "New Item", result[:label]
        assert_equal "https://example.com/items/7", result[:description]
        assert_equal SourceMonitor::Engine.routes.url_helpers.item_path(7), result[:path]
      end

      test "fetch event includes source domain as url_display" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :fetch_log,
          id: 10,
          occurred_at: Time.current,
          success: true,
          items_created: 2,
          items_updated: 0,
          source_feed_url: "https://blog.example.com/feed.xml"
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_equal "blog.example.com", result[:url_display]
        assert_equal "https://blog.example.com/feed.xml", result[:url_href]
      end

      test "fetch event with nil source_feed_url has nil url_display" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :fetch_log,
          id: 11,
          occurred_at: Time.current,
          success: false,
          items_created: 0,
          items_updated: 0,
          source_feed_url: nil
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_nil result[:url_display]
        assert_equal :failure, result[:status]
      end

      test "failure fetch event still includes url_display" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :fetch_log,
          id: 12,
          occurred_at: Time.current,
          success: false,
          items_created: 0,
          items_updated: 0,
          source_feed_url: "https://failing-feed.example.org/rss"
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_equal "failing-feed.example.org", result[:url_display]
        assert_equal :failure, result[:status]
      end

      test "scrape event includes item url as url_display" do
        event = SourceMonitor::Dashboard::RecentActivity::Event.new(
          type: :scrape_log,
          id: 20,
          occurred_at: Time.current,
          success: true,
          scraper_adapter: "readability",
          item_url: "https://example.com/articles/42"
        )

        presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
          [ event ],
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        result = presenter.to_a.first
        assert_equal "https://example.com/articles/42", result[:url_display]
        assert_equal "https://example.com/articles/42", result[:url_href]
      end
    end
  end
end
