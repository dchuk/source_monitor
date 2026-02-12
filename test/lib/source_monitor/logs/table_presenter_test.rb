# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Logs
    class TablePresenterTest < ActiveSupport::TestCase
      include SourceMonitor::Engine.routes.url_helpers

      def setup
        @source = create_source!(name: "Presenter Source")
        @item = SourceMonitor::Item.create!(
          source: @source,
          guid: SecureRandom.uuid,
          title: "Presenter Item",
          url: "https://example.com/articles/presenter"
        )

        @fetch_log = SourceMonitor::FetchLog.create!(
          source: @source,
          success: true,
          http_status: 204,
          items_created: 5,
          items_updated: 2,
          items_failed: 0,
          started_at: Time.current - 10.minutes
        )

        @scrape_log = SourceMonitor::ScrapeLog.create!(
          source: @source,
          item: @item,
          success: false,
          http_status: 500,
          scraper_adapter: "readability",
          duration_ms: 800,
          started_at: Time.current - 5.minutes,
          error_message: "Failure"
        )

        @health_check_log = SourceMonitor::HealthCheckLog.create!(
          source: @source,
          success: true,
          http_status: 200,
          started_at: Time.current - 2.minutes,
          duration_ms: 150
        )

        [ @fetch_log, @scrape_log, @health_check_log ].each(&:reload)
      end

      test "builds typed row view models" do
        result = SourceMonitor::Logs::Query.new(params: {}).call
        presenter = SourceMonitor::Logs::TablePresenter.new(
          entries: result.entries,
          url_helpers: SourceMonitor::Engine.routes.url_helpers
        )

        scrape_row = presenter.rows.find { |row| row.dom_id == "scrape-#{@scrape_log.id}" }
        fetch_row = presenter.rows.find { |row| row.dom_id == "fetch-#{@fetch_log.id}" }
        health_row = presenter.rows.find { |row| row.dom_id == "health-check-#{@health_check_log.id}" }

        assert_equal "Scrape", scrape_row.type_label
        assert_equal "Presenter Item", scrape_row.primary_label
        assert_equal "readability", scrape_row.adapter
        assert scrape_row.failure?
        assert_equal scrape_log_path(@scrape_log), scrape_row.detail_path
        assert_equal :scrape, scrape_row.type_variant
        assert_equal "Failure", scrape_row.status_label
        assert_equal :failure, scrape_row.status_variant
        assert_equal "Presenter Source", scrape_row.source_label
        assert_equal source_path(@source), scrape_row.source_path
        assert_match(/500/, scrape_row.http_summary)
        assert_equal "#{@scrape_log.duration_ms} ms", scrape_row.metrics_summary
        assert_equal "scrape-#{@scrape_log.id}", scrape_row.dom_id
        assert_equal "scrape", scrape_row.type_slug
        assert_equal item_path(@item), scrape_row.primary_path
        assert_equal "https://example.com/articles/presenter", scrape_row.url_label
        assert_equal "https://example.com/articles/presenter", scrape_row.url_href

        assert_equal "Fetch", fetch_row.type_label
        assert_equal "Presenter Source", fetch_row.primary_label
        assert_equal "+5 / ~2 / ✕0", fetch_row.metrics_summary
        assert fetch_row.success?
        assert_equal fetch_log_path(@fetch_log), fetch_row.detail_path
        assert_equal "Presenter Source", fetch_row.source_label
        assert_equal source_path(@source), fetch_row.source_path
        assert_equal "Success", fetch_row.status_label
        assert_equal :success, fetch_row.status_variant
        assert_equal :fetch, fetch_row.type_variant
        assert_equal "fetch-#{@fetch_log.id}", fetch_row.dom_id
        assert_equal "fetch", fetch_row.type_slug
        assert_equal "Presenter Source", fetch_row.primary_label
        assert_equal source_path(@source), fetch_row.primary_path
        assert_equal URI.parse(@source.feed_url).host, fetch_row.url_label
        assert_equal @source.feed_url, fetch_row.url_href

        assert_equal "Health Check", health_row.type_label
        assert_equal "Presenter Source", health_row.primary_label
        assert health_row.success?
        assert_equal "200", health_row.http_summary
        assert_equal "150 ms", health_row.metrics_summary
        assert_nil health_row.detail_path
        assert_equal :health_check, health_row.type_variant
        assert_equal "Success", health_row.status_label
        assert_equal :success, health_row.status_variant
        assert_equal "health-check-#{@health_check_log.id}", health_row.dom_id
        assert_equal "health-check", health_row.type_slug
        assert health_row.health_check?
        refute health_row.fetch?
        refute health_row.scrape?
        assert_equal source_path(@source), health_row.primary_path
        assert_nil health_row.url_label
        assert_nil health_row.url_href
      end
    end
  end
end
