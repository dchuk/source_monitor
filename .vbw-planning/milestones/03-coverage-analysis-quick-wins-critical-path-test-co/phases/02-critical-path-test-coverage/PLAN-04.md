---
phase: 2
plan: 4
title: dashboard-and-analytics-tests
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `bin/rails test test/lib/source_monitor/dashboard/queries_test.rb test/lib/source_monitor/analytics/sources_index_metrics_test.rb test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb` exits 0 with zero failures"
    - "Coverage report shows lib/source_monitor/dashboard/queries.rb has fewer than 15 uncovered lines (down from 66)"
    - "Coverage report shows lib/source_monitor/analytics/sources_index_metrics.rb has fewer than 10 uncovered lines (down from 34)"
    - "Running `bin/rails test` exits 0 with no regressions"
  artifacts:
    - "test/lib/source_monitor/dashboard/queries_test.rb -- extended with tests for StatsQuery, RecentActivityQuery, record_metrics, and Cache"
    - "test/lib/source_monitor/analytics/sources_index_metrics_test.rb -- extended with tests for edge cases in fetch_interval_filter, integer_param, distribution_scope, and selected_fetch_interval_bucket"
  key_links:
    - "REQ-04 substantially satisfied -- Dashboard::Queries branch coverage above 80%"
    - "REQ-07 substantially satisfied -- SourcesIndexMetrics branch coverage above 80%"
---

# Plan 04: dashboard-and-analytics-tests

## Objective

Close the coverage gaps in `lib/source_monitor/dashboard/queries.rb` (66 uncovered lines) and `lib/source_monitor/analytics/sources_index_metrics.rb` (34 uncovered lines). The existing tests cover caching, basic stats, recent_activity events, job_metrics with stub, and upcoming_fetch_schedule groups. This plan targets the remaining uncovered branches: StatsQuery SQL generation and integer_value, RecentActivityQuery's build_event and the three sub-queries, record_metrics branches for each query type, Cache miss/hit paths, SourcesIndexMetrics' fetch_interval_filter with various param combinations, integer_param sanitization, distribution_scope with ransack, and selected_fetch_interval_bucket matching logic.

## Context

<context>
@lib/source_monitor/dashboard/queries.rb -- 357 lines with StatsQuery, RecentActivityQuery, Cache, record_metrics
@lib/source_monitor/analytics/sources_index_metrics.rb -- 93 lines with fetch_interval_filter, integer_param, distribution_scope
@test/lib/source_monitor/dashboard/queries_test.rb -- existing test file with 7 tests
@test/lib/source_monitor/analytics/sources_index_metrics_test.rb -- existing test file with 3 tests
@lib/source_monitor/dashboard/upcoming_fetch_schedule.rb -- UpcomingFetchSchedule with Group struct
@config/coverage_baseline.json -- lists uncovered lines for both files

**Decomposition rationale:** Dashboard::Queries and SourcesIndexMetrics share a read-only analytics theme and can be covered in a single plan without file conflicts. Their combined gap (100 lines) is manageable in 4 tasks. The queries_test.rb file already has good infrastructure (count_sql_queries helper, setup with delete_all).

**Trade-offs considered:**
- StatsQuery and RecentActivityQuery use raw SQL -- tests need real database records, not mocks.
- record_metrics calls SourceMonitor::Metrics.gauge -- we verify gauge values were set.
- The SourcesIndexMetrics distribution_scope branch with ransack requires a scope that responds to .ransack -- the Source model does.
- Some tests for integer_param can test edge cases (non-numeric, XSS-like strings) for both sanitization and type safety.
</context>

## Tasks

### Task 1: Test StatsQuery SQL branches and integer_value

- **name:** test-stats-query-branches
- **files:**
  - `test/lib/source_monitor/dashboard/queries_test.rb`
- **action:** Add tests covering lines 142-204 (StatsQuery). Specifically:
  1. Test stats returns correct counts with mixed active/inactive sources, sources with failures (failure_count > 0, last_error present), items, and fetch logs from today vs yesterday
  2. Test stats[:failed_sources] counts sources that have failure_count > 0 OR last_error IS NOT NULL OR last_error_at IS NOT NULL (the OR conditions at lines 186-190)
  3. Test stats[:fetches_today] only counts fetch logs with started_at >= start_of_day (line 172)
  4. Test stats with zero sources and zero items returns all zeros
  5. Test record_stats_metrics sets gauge values for total_sources, active_sources, failed_sources, total_items, fetches_today (lines 105-111)
  Create specific database records to exercise each condition.
- **verify:** `bin/rails test test/lib/source_monitor/dashboard/queries_test.rb -n /stats_query|failed_sources|fetches_today|stats_metrics/i` exits 0
- **done:** Lines 142-204, 105-111 covered.

### Task 2: Test RecentActivityQuery build_event and sub-queries

- **name:** test-recent-activity-query-details
- **files:**
  - `test/lib/source_monitor/dashboard/queries_test.rb`
- **action:** Add tests covering lines 206-335 (RecentActivityQuery). Specifically:
  1. Test that build_event produces Event objects with correct type symbol (:fetch_log, :scrape_log, :item), correct fields (occurred_at, success, items_created, items_updated, scraper_adapter, item_title, item_url, source_name, source_id)
  2. Test that fetch_log events have success based on the boolean column, items_created/items_updated from the log
  3. Test that scrape_log events include scraper_adapter and source_name (via JOIN)
  4. Test that item events have item_title, item_url, source_name (via JOIN), and success_flag always 1
  5. Test that events are ordered by occurred_at DESC and limited correctly
  6. Test record_metrics for :recent_activity sets dashboard_recent_activity_events_count and dashboard_recent_activity_limit gauges (lines 96-97)
  Create a mix of fetch_logs, scrape_logs, and items with specific timestamps to verify ordering and limit.
- **verify:** `bin/rails test test/lib/source_monitor/dashboard/queries_test.rb -n /recent_activity_query|build_event|event_type|event_order/i` exits 0
- **done:** Lines 206-335, 96-97 covered.

### Task 3: Test record_metrics branches and Cache edge cases

- **name:** test-record-metrics-and-cache
- **files:**
  - `test/lib/source_monitor/dashboard/queries_test.rb`
- **action:** Add tests covering lines 75-103 (measure and record_metrics), lines 124-140 (Cache). Specifically:
  1. Test record_metrics for :job_metrics sets dashboard_job_metrics_queue_count gauge (line 99)
  2. Test record_metrics for :upcoming_fetch_schedule sets dashboard_fetch_schedule_group_count gauge (line 101)
  3. Test that measure instruments ActiveSupport::Notifications with correct event name and payload (lines 81-83)
  4. Test Cache.fetch returns cached value on second call without calling block again (lines 130-133)
  5. Test Cache.fetch with different keys calls block for each (line 129 store.key? check)
  Use SourceMonitor::Metrics.reset! before each test and check gauge values after.
- **verify:** `bin/rails test test/lib/source_monitor/dashboard/queries_test.rb -n /record_metrics|cache_behavior|measure_instrument/i` exits 0
- **done:** Lines 75-103, 124-140 covered.

### Task 4: Test SourcesIndexMetrics edge cases

- **name:** test-sources-index-metrics-edges
- **files:**
  - `test/lib/source_monitor/analytics/sources_index_metrics_test.rb`
- **action:** Add tests covering remaining uncovered lines in sources_index_metrics.rb. Specifically:
  1. Test fetch_interval_filter returns nil when no interval params present (line 49)
  2. Test fetch_interval_filter with only min param (gteq) and nil max
  3. Test fetch_interval_filter prefers fetch_interval_minutes_lt over fetch_interval_minutes_lteq when both present
  4. Test integer_param returns nil for blank value (line 71), returns nil for non-numeric string after sanitization (line 77-79), returns integer for valid string
  5. Test selected_fetch_interval_bucket returns nil when no filter is set (line 28)
  6. Test selected_fetch_interval_bucket matches bucket where min.nil? (first bucket) when filter min is nil
  7. Test distribution_scope uses ransack when filtered_params are present and scope responds to ransack (lines 62-63)
  8. Test distribution_scope returns base_scope when filtered_params are empty (line 65)
  9. Test distribution_source_ids with a scope that responds to pluck vs one that doesn't (lines 83-88)
- **verify:** `bin/rails test test/lib/source_monitor/analytics/sources_index_metrics_test.rb -n /fetch_interval_filter|integer_param|selected_bucket|distribution_scope/i` exits 0
- **done:** All remaining uncovered lines in sources_index_metrics.rb covered.

## Verification

1. `bin/rails test test/lib/source_monitor/dashboard/queries_test.rb` exits 0
2. `bin/rails test test/lib/source_monitor/analytics/sources_index_metrics_test.rb` exits 0
3. `COVERAGE=1 bin/rails test test/lib/source_monitor/dashboard/queries_test.rb test/lib/source_monitor/analytics/sources_index_metrics_test.rb` shows both files with >80% branch coverage
4. `bin/rails test` exits 0 (no regressions)

## Success Criteria

- [ ] Dashboard::Queries coverage drops from 66 uncovered lines to fewer than 15
- [ ] SourcesIndexMetrics coverage drops from 34 uncovered lines to fewer than 10
- [ ] StatsQuery SQL branches fully tested
- [ ] RecentActivityQuery event building and sub-queries tested
- [ ] record_metrics branches for all query types tested
- [ ] Cache miss/hit behavior tested
- [ ] SourcesIndexMetrics filter, sanitization, and distribution scope tested
- [ ] REQ-04 and REQ-07 substantially satisfied
