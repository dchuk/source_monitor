# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Logs
    class QueryTest < ActiveSupport::TestCase
      REFERENCE_TIME = Time.zone.parse("2025-10-15 10:00:00")

      setup_once do
        reference_time = REFERENCE_TIME

        @source_a_id = create_source!(name: "Source A").id
        @source_b_id = create_source!(name: "Source B").id

        @item_a_id = SourceMonitor::Item.create!(
          source_id: @source_a_id,
          guid: SecureRandom.uuid,
          title: "Primary Item",
          url: "https://example.com/articles/primary"
        ).id

        @item_b_id = SourceMonitor::Item.create!(
          source_id: @source_b_id,
          guid: SecureRandom.uuid,
          title: "Secondary Item",
          url: "https://example.com/articles/secondary"
        ).id

        @recent_fetch_id = SourceMonitor::FetchLog.create!(
          source_id: @source_a_id,
          success: true,
          http_status: 200,
          items_created: 2,
          items_updated: 1,
          items_failed: 0,
          started_at: reference_time - 30.minutes,
          error_message: "OK"
        ).id

        @older_fetch_id = SourceMonitor::FetchLog.create!(
          source_id: @source_b_id,
          success: false,
          http_status: 500,
          items_created: 0,
          items_updated: 0,
          items_failed: 1,
          started_at: reference_time - 3.days,
          error_message: "Timeout while fetching"
        ).id

        @recent_scrape_id = SourceMonitor::ScrapeLog.create!(
          source_id: @source_a_id,
          item_id: @item_a_id,
          success: false,
          http_status: 502,
          scraper_adapter: "readability",
          duration_ms: 1200,
          started_at: reference_time - 20.minutes,
          error_message: "Readability parse error"
        ).id

        @older_scrape_id = SourceMonitor::ScrapeLog.create!(
          source_id: @source_b_id,
          item_id: @item_b_id,
          success: true,
          http_status: 200,
          scraper_adapter: "mercury",
          duration_ms: 900,
          started_at: reference_time - 5.days
        ).id

        @health_check_id = SourceMonitor::HealthCheckLog.create!(
          source_id: @source_a_id,
          success: true,
          http_status: 204,
          started_at: reference_time - 10.minutes,
          duration_ms: 400
        ).id
      end

      setup do
        @source_a = SourceMonitor::Source.find(@source_a_id)
        @source_b = SourceMonitor::Source.find(@source_b_id)
        @item_a = SourceMonitor::Item.find(@item_a_id)
        @item_b = SourceMonitor::Item.find(@item_b_id)
        @recent_fetch_entry = SourceMonitor::FetchLog.find(@recent_fetch_id).log_entry
        @older_fetch_entry = SourceMonitor::FetchLog.find(@older_fetch_id).log_entry
        @recent_scrape_entry = SourceMonitor::ScrapeLog.find(@recent_scrape_id).log_entry
        @older_scrape_entry = SourceMonitor::ScrapeLog.find(@older_scrape_id).log_entry
        @health_check_entry = SourceMonitor::HealthCheckLog.find(@health_check_id).log_entry
      end

      test "returns entries ordered by newest started_at first" do
        result = SourceMonitor::Logs::Query.new(params: {}).call

        assert_equal [ @health_check_entry.id, @recent_scrape_entry.id, @recent_fetch_entry.id, @older_fetch_entry.id, @older_scrape_entry.id ],
                     result.entries.map(&:id)
        assert_equal [ :health_check, :scrape, :fetch, :fetch, :scrape ],
                     result.entries.map(&:log_type)
      end

      test "filters by log type" do
        result = SourceMonitor::Logs::Query.new(params: { log_type: "fetch" }).call

        assert_equal [ :fetch, :fetch ], result.entries.map(&:log_type)
        assert_equal [ @recent_fetch_entry.id, @older_fetch_entry.id ], result.entries.map(&:id)
      end

      test "filters health check logs" do
        result = SourceMonitor::Logs::Query.new(params: { log_type: "health_check" }).call

        assert_equal [ :health_check ], result.entries.map(&:log_type)
        assert_equal [ @health_check_entry.id ], result.entries.map(&:id)
      end

      test "filters by status" do
        result = SourceMonitor::Logs::Query.new(params: { status: "failed" }).call

        assert_equal [ :scrape, :fetch ], result.entries.map(&:log_type)
        assert_equal [ @recent_scrape_entry.id, @older_fetch_entry.id ], result.entries.map(&:id)
        assert result.entries.all? { |entry| entry.success? == false }
      end

      test "filters by timeframe shortcut" do
        travel_to(REFERENCE_TIME) do
          result = SourceMonitor::Logs::Query.new(params: { timeframe: "24h" }).call
          assert_equal [ @health_check_entry.id, @recent_scrape_entry.id, @recent_fetch_entry.id ], result.entries.map(&:id)
        end
      end

      test "filters by explicit started_at range" do
        travel_to(REFERENCE_TIME) do
          result = SourceMonitor::Logs::Query.new(
            params: {
              started_after: 36.hours.ago.iso8601,
              started_before: 10.minutes.from_now.iso8601
            }
          ).call

          assert_equal [ @health_check_entry.id, @recent_scrape_entry.id, @recent_fetch_entry.id ], result.entries.map(&:id)
        end
      end

      test "filters by source id" do
        result = SourceMonitor::Logs::Query.new(params: { source_id: @source_a.id.to_s }).call

        assert_equal [ :health_check, :scrape, :fetch ], result.entries.map(&:log_type)
        assert result.entries.all? { |entry| entry.source_id == @source_a.id }
      end

      test "filters scrape logs by item id" do
        result = SourceMonitor::Logs::Query.new(params: { item_id: @item_a.id }).call

        assert_equal [ :scrape ], result.entries.map(&:log_type)
        assert_equal [ @recent_scrape_entry.id ], result.entries.map(&:id)
      end

      test "performs case-insensitive search across title, source, and error message" do
        result = SourceMonitor::Logs::Query.new(params: { search: "timeout" }).call

        assert_equal [ @older_fetch_entry.id ], result.entries.map(&:id)
      end

      test "paginates results using configured per_page" do
        30.times do |index|
          SourceMonitor::FetchLog.create!(
            source: @source_a,
            success: true,
            http_status: 200,
            items_created: 0,
            items_updated: 0,
            items_failed: 0,
            started_at: (index + 31).minutes.ago
          )
        end

        result_page_1 = SourceMonitor::Logs::Query.new(params: { page: 1, per_page: 25 }).call
        result_page_2 = SourceMonitor::Logs::Query.new(params: { page: 2, per_page: 25 }).call

        assert_equal 25, result_page_1.entries.count
        assert result_page_1.has_next_page?
        assert_not result_page_1.has_previous_page?

        assert result_page_2.entries.present?
        assert result_page_2.has_previous_page?
      end

      test "Result#next_page returns page + 1 when has_next_page" do
        result = SourceMonitor::Logs::Query::Result.new(
          entries: [],
          page: 2,
          per_page: 25,
          has_next_page: true,
          has_previous_page: true,
          total_count: 100
        )

        assert_equal 3, result.next_page
      end

      test "Result#next_page returns nil when no next page" do
        result = SourceMonitor::Logs::Query::Result.new(
          entries: [],
          page: 4,
          per_page: 25,
          has_next_page: false,
          has_previous_page: true,
          total_count: 100
        )

        assert_nil result.next_page
      end

      test "Result#previous_page returns page - 1 when has_previous_page" do
        result = SourceMonitor::Logs::Query::Result.new(
          entries: [],
          page: 3,
          per_page: 25,
          has_next_page: false,
          has_previous_page: true,
          total_count: 100
        )

        assert_equal 2, result.previous_page
      end

      test "Result#previous_page returns nil when no previous page" do
        result = SourceMonitor::Logs::Query::Result.new(
          entries: [],
          page: 1,
          per_page: 25,
          has_next_page: true,
          has_previous_page: false,
          total_count: 100
        )

        assert_nil result.previous_page
      end

      test "Result#previous_page returns at least 1" do
        result = SourceMonitor::Logs::Query::Result.new(
          entries: [],
          page: 1,
          per_page: 25,
          has_next_page: false,
          has_previous_page: true,
          total_count: 100
        )

        assert_equal 1, result.previous_page
      end

      test "sanitizes invalid parameters without raising" do
        result = SourceMonitor::Logs::Query.new(
          params: {
            log_type: "<svg>",
            status: "failed<script>",
            source_id: "1; DROP TABLE fetch_logs;",
            timeframe: "bogus"
          }
        ).call

        assert_equal [ @recent_scrape_entry.id, @older_fetch_entry.id ],
                     result.entries.map(&:id)
      end
    end
  end
end
