# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class QueriesTest < ActiveSupport::TestCase
      include ActiveSupport::Testing::TimeHelpers

      setup do
        SourceMonitor::Metrics.reset!
        clean_source_monitor_tables!
      end

      test "stats caches results and minimizes SQL calls" do
        SourceMonitor::Source.create!(
          name: "Cached Source",
          feed_url: "https://example.com/cache.xml",
          active: true,
          failure_count: 1,
          last_error: "Timeout"
        )

        queries = SourceMonitor::Dashboard::Queries.new

        first_call_queries = count_sql_queries { queries.stats }
        assert_operator first_call_queries, :<=, 3, "expected at most three SQL statements for stats"

        cached_call_queries = count_sql_queries { queries.stats }
        assert_equal 0, cached_call_queries, "expected cached stats to avoid additional SQL"
      end

      test "recent_activity returns events without route data and caches by limit" do
        source = SourceMonitor::Source.create!(
          name: "Activity Source",
          feed_url: "https://example.com/activity.xml"
        )

        SourceMonitor::FetchLog.create!(
          source:,
          started_at: Time.current,
          success: true,
          items_created: 2,
          items_updated: 1
        )

        item = SourceMonitor::Item.create!(
          source:,
          guid: "recent-item",
          url: "https://example.com/items/1",
          title: "Recent Item",
          created_at: Time.current,
          published_at: Time.current
        )

        SourceMonitor::ScrapeLog.create!(
          source:,
          item:,
          started_at: Time.current,
          success: false,
          scraper_adapter: "readability"
        )

        queries = SourceMonitor::Dashboard::Queries.new

        events = queries.recent_activity(limit: 5)
        assert events.all? { |event| event.is_a?(SourceMonitor::Dashboard::RecentActivity::Event) }
        assert events.none? { |event| event.respond_to?(:path) }, "events should not expose routing information"

        cached_call_queries = count_sql_queries { queries.recent_activity(limit: 5) }
        assert_equal 0, cached_call_queries, "expected cached recent activity for identical limit"

        different_limit_queries = count_sql_queries { queries.recent_activity(limit: 2) }
        assert_operator different_limit_queries, :<=, 2, "expected at most two SQL statements for distinct limit cache"
      end

      test "stats instrumentation records duration metrics" do
        queries = SourceMonitor::Dashboard::Queries.new
        events = []

        subscriber = ActiveSupport::Notifications.subscribe("source_monitor.dashboard.stats") do |*args|
          events << ActiveSupport::Notifications::Event.new(*args)
        end

        queries.stats

        assert_equal 1, events.size, "expected a dashboard stats instrumentation event"
        payload = events.first.payload
        assert payload[:duration_ms].present?, "expected payload duration in milliseconds"
        assert payload[:recorded_at].present?, "expected payload recorded_at timestamp"

        assert SourceMonitor::Metrics.gauge_value(:dashboard_stats_duration_ms), "expected metrics gauge for duration"
        assert SourceMonitor::Metrics.gauge_value(:dashboard_stats_last_run_at_epoch), "expected metrics gauge for last run timestamp"

        SourceMonitor::Metrics.reset!
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      test "job_metrics maps summaries to configured queue roles" do
        queries = SourceMonitor::Dashboard::Queries.new
        fetch_summary = SourceMonitor::Jobs::SolidQueueMetrics::QueueSummary.new(
          queue_name: SourceMonitor.queue_name(:fetch),
          ready_count: 2,
          scheduled_count: 1,
          failed_count: 0,
          recurring_count: 1,
          paused: false,
          last_enqueued_at: Time.current,
          last_started_at: nil,
          last_finished_at: nil,
          available: true
        )

        SourceMonitor::Jobs::SolidQueueMetrics.stub(:call, { SourceMonitor.queue_name(:fetch) => fetch_summary }) do
          metrics = queries.job_metrics

          assert_equal [ :fetch, :scrape ], metrics.map { |row| row[:role] }
          fetch_row = metrics.detect { |row| row[:role] == :fetch }
          assert_equal fetch_summary, fetch_row[:summary]

          scrape_row = metrics.detect { |row| row[:role] == :scrape }
          assert_equal SourceMonitor.queue_name(:scrape), scrape_row[:queue_name]
          assert_equal 0, scrape_row[:summary].ready_count
          refute scrape_row[:summary].available
        end
      end

      test "upcoming_fetch_schedule caches grouped sources" do
        source = SourceMonitor::Source.create!(
          name: "Schedule Source",
          feed_url: "https://example.com/schedule.xml",
          next_fetch_at: Time.current + 15.minutes
        )

        queries = SourceMonitor::Dashboard::Queries.new

        first_groups = queries.upcoming_fetch_schedule.groups
        assert_equal 1, first_groups.find { |group| group.key == "0-30" }.sources.size

        SourceMonitor::Source.where(id: source.id).update_all(next_fetch_at: Time.current + 5.hours)

        cached_groups = queries.upcoming_fetch_schedule.groups
        assert_equal 1, cached_groups.find { |group| group.key == "0-30" }.sources.size
      end

      test "recent_activity caches results per limit key" do
        queries = SourceMonitor::Dashboard::Queries.new
        fake_cache = Struct.new(:calls) do
          def fetch(key)
            calls << key
            yield
          end
        end.new([])

        queries.instance_variable_set(:@cache, fake_cache)

        fake_query = Minitest::Mock.new
        fake_query.expect :call, []

        SourceMonitor::Dashboard::Queries::RecentActivityQuery.stub(:new, ->(**kwargs) {
          assert_equal 5, kwargs[:limit]
          fake_query
        }) { queries.recent_activity(limit: 5) }

        fake_query.verify

        assert_includes fake_cache.calls, [ :recent_activity, 5 ]
      end

      test "recent_activity_query sanitizes SQL with the provided limit" do
        query = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 3)

        sql = query.send(:sanitized_sql)

        assert_includes sql, "LIMIT 3"
      end

      # === Task 1: StatsQuery SQL branches and integer_value ===

      test "stats returns correct counts for active, failed, and total sources" do
        create_source!(name: "Active OK", active: true, failure_count: 0, last_error: nil, last_error_at: nil)
        create_source!(name: "Active Failed", active: true, failure_count: 3, last_error: "Timeout", last_error_at: 1.hour.ago)
        create_source!(name: "Inactive OK", active: false, failure_count: 0, last_error: nil, last_error_at: nil)
        create_source!(name: "Inactive Failed Count", active: false, failure_count: 1, last_error: nil, last_error_at: nil)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 4, stats[:total_sources]
        assert_equal 2, stats[:active_sources]
        assert_equal 2, stats[:failed_sources]
      end

      test "stats counts sources with only last_error as failed" do
        create_source!(name: "Error Only", failure_count: 0, last_error: "Connection refused", last_error_at: nil)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:failed_sources]
      end

      test "stats counts sources with only last_error_at as failed" do
        create_source!(name: "Error At Only", failure_count: 0, last_error: nil, last_error_at: 1.hour.ago)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:failed_sources]
      end

      test "stats returns zero failed when no failure indicators present" do
        create_source!(name: "Healthy", failure_count: 0, last_error: nil, last_error_at: nil)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 0, stats[:failed_sources]
      end

      test "stats total_items counts all items" do
        source = create_source!(name: "Items Source")
        3.times do |i|
          SourceMonitor::Item.create!(
            source: source,
            guid: "item-#{i}",
            url: "https://example.com/item-#{i}",
            title: "Item #{i}",
            published_at: Time.current
          )
        end

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 3, stats[:total_items]
      end

      test "stats fetches_today counts only fetches from today" do
        source = create_source!(name: "Fetch Source")
        now = Time.current
        today_noon = now.in_time_zone.beginning_of_day + 12.hours

        SourceMonitor::FetchLog.create!(source: source, started_at: today_noon - 1.hour, success: true)
        SourceMonitor::FetchLog.create!(source: source, started_at: today_noon - 2.hours, success: false)
        SourceMonitor::FetchLog.create!(source: source, started_at: today_noon - 2.days, success: true)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: today_noon).call

        assert_equal 2, stats[:fetches_today]
      end

      test "stats returns all integers even with empty database" do
        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 0, stats[:total_sources]
        assert_equal 0, stats[:active_sources]
        assert_equal 0, stats[:failed_sources]
        assert_equal 0, stats[:total_items]
        assert_equal 0, stats[:fetches_today]
        stats.each_value { |v| assert_kind_of Integer, v }
      end

      test "stats integer_value handles nil from SQL" do
        query = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current)
        assert_equal 0, query.send(:integer_value, nil)
      end

      test "stats integer_value handles string from SQL" do
        query = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current)
        assert_equal 42, query.send(:integer_value, "42")
      end

      # === Task 2: RecentActivityQuery build_event and sub-queries ===

      test "recent_activity returns fetch_log events with correct attributes" do
        source = create_source!(name: "Fetch Source")
        fetch_log = SourceMonitor::FetchLog.create!(
          source: source,
          started_at: Time.current,
          success: true,
          items_created: 5,
          items_updated: 2
        )

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call
        fetch_event = events.find { |e| e.type == :fetch_log }

        assert_not_nil fetch_event
        assert_equal fetch_log.id, fetch_event.id
        assert fetch_event.success?
        assert_equal 5, fetch_event.items_created
        assert_equal 2, fetch_event.items_updated
        assert_nil fetch_event.scraper_adapter
        assert_nil fetch_event.item_title
        assert_nil fetch_event.item_url
      end

      test "recent_activity returns scrape_log events with source name and adapter" do
        source = create_source!(name: "Scrape Source")
        item = SourceMonitor::Item.create!(
          source: source,
          guid: "scrape-item",
          url: "https://example.com/scrape",
          title: "Scrape Item",
          published_at: Time.current
        )
        scrape_log = SourceMonitor::ScrapeLog.create!(
          source: source,
          item: item,
          started_at: Time.current,
          success: false,
          scraper_adapter: "readability"
        )

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call
        scrape_event = events.find { |e| e.type == :scrape_log }

        assert_not_nil scrape_event
        assert_equal scrape_log.id, scrape_event.id
        refute scrape_event.success?
        assert_equal "readability", scrape_event.scraper_adapter
        assert_equal "Scrape Source", scrape_event.source_name
        assert_equal source.id, scrape_event.source_id
      end

      test "recent_activity returns item events with title and url" do
        source = create_source!(name: "Item Source")
        item = SourceMonitor::Item.create!(
          source: source,
          guid: "activity-item",
          url: "https://example.com/article",
          title: "My Article",
          published_at: Time.current
        )

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call
        item_event = events.find { |e| e.type == :item }

        assert_not_nil item_event
        assert_equal item.id, item_event.id
        assert item_event.success?
        assert_equal "My Article", item_event.item_title
        assert_equal "https://example.com/article", item_event.item_url
        assert_equal "Item Source", item_event.source_name
        assert_equal source.id, item_event.source_id
      end

      test "recent_activity orders events by occurred_at descending" do
        source = create_source!(name: "Order Source")

        SourceMonitor::FetchLog.create!(source: source, started_at: 3.hours.ago, success: true)
        SourceMonitor::Item.create!(
          source: source, guid: "order-item", url: "https://example.com/order",
          title: "Order Item", published_at: 1.hour.ago, created_at: 1.hour.ago
        )
        SourceMonitor::FetchLog.create!(source: source, started_at: 2.hours.ago, success: true)

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call

        timestamps = events.map(&:occurred_at).compact
        assert_equal timestamps.sort.reverse, timestamps
      end

      test "recent_activity respects limit parameter" do
        source = create_source!(name: "Limit Source")
        5.times do |i|
          SourceMonitor::FetchLog.create!(
            source: source,
            started_at: i.hours.ago,
            success: true
          )
        end

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 2).call

        assert_equal 2, events.size
      end

      test "recent_activity includes all three event types in union" do
        source = create_source!(name: "Union Source")
        item = SourceMonitor::Item.create!(
          source: source, guid: "union-item", url: "https://example.com/union",
          title: "Union Item", published_at: Time.current
        )
        SourceMonitor::FetchLog.create!(source: source, started_at: Time.current, success: true)
        SourceMonitor::ScrapeLog.create!(
          source: source, item: item, started_at: Time.current, success: true, scraper_adapter: "test"
        )

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call
        types = events.map(&:type).uniq.sort

        assert_includes types, :fetch_log
        assert_includes types, :item
        assert_includes types, :scrape_log
      end

      test "recent_activity build_event handles failed fetch_log with success_flag 0" do
        source = create_source!(name: "Failed Fetch")
        SourceMonitor::FetchLog.create!(source: source, started_at: Time.current, success: false)

        events = SourceMonitor::Dashboard::Queries::RecentActivityQuery.new(limit: 10).call
        fetch_event = events.find { |e| e.type == :fetch_log }

        refute fetch_event.success?
      end

      # === Task 3: record_metrics branches and Cache edge cases ===

      test "record_metrics records stats gauge values" do
        source = create_source!(name: "Metric Source", active: true, failure_count: 1, last_error: "err")
        SourceMonitor::Item.create!(
          source: source, guid: "metric-item", url: "https://example.com/m",
          title: "M", published_at: Time.current
        )

        queries = SourceMonitor::Dashboard::Queries.new
        queries.stats

        assert_equal 1, SourceMonitor::Metrics.gauge_value("dashboard_stats_total_sources")
        assert_equal 1, SourceMonitor::Metrics.gauge_value("dashboard_stats_active_sources")
        assert_equal 1, SourceMonitor::Metrics.gauge_value("dashboard_stats_failed_sources")
        assert_equal 1, SourceMonitor::Metrics.gauge_value("dashboard_stats_total_items")
        assert_kind_of Numeric, SourceMonitor::Metrics.gauge_value("dashboard_stats_fetches_today")
      end

      test "record_metrics records recent_activity count and limit" do
        queries = SourceMonitor::Dashboard::Queries.new
        queries.recent_activity(limit: 7)

        assert_kind_of Integer, SourceMonitor::Metrics.gauge_value("dashboard_recent_activity_events_count")
        assert_equal 7, SourceMonitor::Metrics.gauge_value("dashboard_recent_activity_limit")
      end

      test "record_metrics records job_metrics queue count" do
        queries = SourceMonitor::Dashboard::Queries.new
        SourceMonitor::Jobs::SolidQueueMetrics.stub(:call, {}) do
          queries.job_metrics
        end

        assert_equal 2, SourceMonitor::Metrics.gauge_value("dashboard_job_metrics_queue_count")
      end

      test "record_metrics records upcoming_fetch_schedule group count" do
        queries = SourceMonitor::Dashboard::Queries.new
        queries.upcoming_fetch_schedule

        assert_kind_of Integer, SourceMonitor::Metrics.gauge_value("dashboard_fetch_schedule_group_count")
      end

      test "cache returns cached value for duplicate keys without re-executing block" do
        cache = SourceMonitor::Dashboard::Queries::Cache.new
        call_count = 0

        result1 = cache.fetch(:test_key) { call_count += 1; "value" }
        result2 = cache.fetch(:test_key) { call_count += 1; "different" }

        assert_equal "value", result1
        assert_equal "value", result2
        assert_equal 1, call_count
      end

      test "cache distinguishes different keys" do
        cache = SourceMonitor::Dashboard::Queries::Cache.new

        cache.fetch(:key_a) { "alpha" }
        cache.fetch(:key_b) { "beta" }

        assert_equal "alpha", cache.fetch(:key_a) { "should not run" }
        assert_equal "beta", cache.fetch(:key_b) { "should not run" }
      end

      test "cache stores nil values without re-executing block" do
        cache = SourceMonitor::Dashboard::Queries::Cache.new
        call_count = 0

        result1 = cache.fetch(:nil_key) { call_count += 1; nil }
        result2 = cache.fetch(:nil_key) { call_count += 1; "not nil" }

        assert_nil result1
        assert_nil result2
        assert_equal 1, call_count
      end

      test "cache stores false values without re-executing block" do
        cache = SourceMonitor::Dashboard::Queries::Cache.new
        call_count = 0

        result1 = cache.fetch(:false_key) { call_count += 1; false }
        result2 = cache.fetch(:false_key) { call_count += 1; true }

        assert_equal false, result1
        assert_equal false, result2
        assert_equal 1, call_count
      end

      test "cache supports array keys for recent_activity limit" do
        cache = SourceMonitor::Dashboard::Queries::Cache.new

        cache.fetch([ :recent_activity, 5 ]) { "five" }
        cache.fetch([ :recent_activity, 10 ]) { "ten" }

        assert_equal "five", cache.fetch([ :recent_activity, 5 ]) { "wrong" }
        assert_equal "ten", cache.fetch([ :recent_activity, 10 ]) { "wrong" }
      end

      private

      def count_sql_queries
        queries = []
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
          next if payload[:name] == "SCHEMA"

          queries << payload[:sql]
        end

        yield
        queries.count
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end
    end
  end
end
