---
phase: "03"
plan: "04"
title: "Health Distribution Badge Counts on Dashboard"
status: complete
---

# Plan 04 Summary: Health Distribution Badge Counts on Dashboard

## What Was Built

Added health status distribution counts to the dashboard. A new query in `StatsQuery` computes active source counts grouped by health_status (healthy, warning, declining, critical), rendered as color-coded inline badges below the existing stats cards. Health distribution metrics are recorded through the existing instrumentation pipeline.

## Tasks Completed

1. **Add health_distribution to StatsQuery** -- Extended `StatsQuery#call` to include a `health_distribution` hash via `Source.active.group(:health_status).count` with zero-defaults for all four statuses.
2. **Render health distribution badges on dashboard** -- Added inline flex badges below stats cards in `_stats.html.erb`. Only non-zero statuses render. Colors match existing HealthBadgeHelper conventions.
3. **Update Dashboard::Queries metrics recording** -- Appended per-status gauge lines to `record_stats_metrics` (e.g., `dashboard_stats_health_healthy`).
4. **Write tests for health distribution** -- Created `stats_query_test.rb` with 4 test cases covering mixed counts, inactive exclusion, zero defaults, and empty active set.

## Files Modified

- `lib/source_monitor/dashboard/queries/stats_query.rb` -- Added `health_distribution` key and private method
- `app/views/source_monitor/dashboard/_stats.html.erb` -- Added badge row with Turbo Stream targeting ID
- `lib/source_monitor/dashboard/queries.rb` -- Appended health gauge lines to `record_stats_metrics`
- `test/lib/source_monitor/dashboard/queries_test.rb` -- Fixed SQL count assertion (3 -> 4) and `each_value` type check for new hash key
- `test/lib/source_monitor/dashboard/stats_query_test.rb` -- NEW: 4 tests for health distribution query

## Commits

- `0296be9` feat(dashboard): add health_distribution to StatsQuery
- `d325251` feat(dashboard): render health distribution badges below stats cards
- `a2b5997` feat(dashboard): record health distribution metrics as gauges
- `d606f66` test(dashboard): add health distribution query tests

## Deviations

- Updated existing `queries_test.rb` to fix two assertions broken by the new `health_distribution` hash key: the SQL query count check (3 -> 4 queries) and the `each_value` Integer type assertion (now skips the Hash-valued key).

## Test Results

47 dashboard tests pass (36 existing + 4 new + 7 other dashboard tests), 0 failures, 0 errors.
