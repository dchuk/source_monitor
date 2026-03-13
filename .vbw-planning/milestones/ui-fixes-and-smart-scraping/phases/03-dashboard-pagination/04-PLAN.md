---
phase: "03"
plan: "04"
title: "Health Distribution Badge Counts on Dashboard"
wave: 1
depends_on: []
must_haves:
  - "Health status distribution query added to StatsQuery"
  - "Badge counts rendered on dashboard stats section"
  - "Aggregate stays above the fold"
  - "Tests cover the query and rendering"
---

# Plan 04: Health Distribution Badge Counts on Dashboard

## Goal

Add health status distribution counts (Healthy N, Warning N, Declining N, Critical N) to the dashboard stats section. The distribution is computed via a new query in `StatsQuery` and rendered as inline badge counts below the existing stats cards.

## Task 1: Add health status distribution to StatsQuery

**What:** Extend `StatsQuery#call` to include a `health_distribution` hash with counts per health status.

**Files to modify:**
- `lib/source_monitor/dashboard/queries/stats_query.rb`

**Implementation details:**
- Add `health_distribution` key to the returned hash
- Query: `SourceMonitor::Source.active.group(:health_status).count` (returns `{ "healthy" => 42, "warning" => 3, ... }`)
- This is a single SQL query: `SELECT health_status, COUNT(*) FROM sources WHERE active = true GROUP BY health_status`
- Ensure all known statuses are present in the result (default to 0 for missing): `%w[healthy warning declining critical].each_with_object({}) { |s, h| h[s] = raw_counts.fetch(s, 0) }`
- Only count active sources (inactive sources don't have meaningful health status)

**Acceptance criteria:**
- `stats[:health_distribution]` returns `{ "healthy" => N, "warning" => N, "declining" => N, "critical" => N }`
- Zero-count statuses still appear in the hash with value 0
- Single additional DB query (GROUP BY), not N+1

## Task 2: Render health distribution badges on dashboard

**What:** Add a row of inline badge counts below the existing stats cards grid.

**Files to modify:**
- `app/views/source_monitor/dashboard/_stats.html.erb`

**Implementation details:**
- Below the existing `grid` of stat cards, add a `<div>` with inline flex badges
- Each badge shows the health status label + count, using the same color scheme from `HealthBadgeHelper`:
  - Healthy: `bg-green-100 text-green-700`
  - Warning: `bg-amber-100 text-amber-700`
  - Declining: `bg-orange-100 text-orange-700`
  - Critical: `bg-rose-100 text-rose-700`
- Badge format: `<span class="inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold [color-classes]">Healthy <span class="font-bold">42</span></span>`
- Only render badges for statuses with count > 0 (don't show "Critical 0" if no critical sources)
- If no active sources exist, don't render the badge row at all
- The badge row uses `id="source_monitor_dashboard_health_distribution"` for Turbo Stream targeting

**Acceptance criteria:**
- Badges appear below stats cards
- Only non-zero statuses show badges
- Colors match existing health status badge convention
- Visible above the fold on standard viewport

## Task 3: Update Dashboard::Queries metrics recording for health distribution

**What:** Record health distribution metrics via the existing instrumentation pattern.

**Files to modify:**
- `lib/source_monitor/dashboard/queries.rb`

**Implementation details:**
- In `record_stats_metrics`, add gauges for each health status count:
  - `SourceMonitor::Metrics.gauge(:dashboard_stats_health_healthy, stats[:health_distribution]["healthy"])`
  - Same for warning, declining, critical
- This follows the existing pattern of recording stat values as gauges

**Acceptance criteria:**
- Health distribution metrics are recorded when stats are computed
- No new notification events needed (reuses existing stats instrumentation)

## Task 4: Write tests for health distribution

**What:** Test the query and verify the badge rendering.

**Files to create:**
- `test/lib/source_monitor/dashboard/stats_query_test.rb`

**Test cases:**
- `test "health_distribution counts active sources by health_status"` -- Create sources with different health statuses, verify counts
- `test "health_distribution excludes inactive sources"` -- Create inactive source with "critical" status, verify it's not counted
- `test "health_distribution includes zero for missing statuses"` -- Only healthy sources exist, verify warning/declining/critical are 0
- `test "health_distribution handles no active sources"` -- No active sources, verify all counts are 0

**Acceptance criteria:**
- All tests pass
- Tests use `create_source!` factory with explicit health_status values
- Tests are isolated (scoped to test-created data)

## File Disjointness (Wave 1)

This plan modifies:
- `lib/source_monitor/dashboard/queries/stats_query.rb`
- `app/views/source_monitor/dashboard/_stats.html.erb`
- `lib/source_monitor/dashboard/queries.rb` (metrics recording only -- different methods than Plan 02's `upcoming_fetch_schedule` method)
- `test/lib/source_monitor/dashboard/stats_query_test.rb` (NEW)

**Conflict analysis with Plan 02:** Both plans modify `lib/source_monitor/dashboard/queries.rb`. However:
- Plan 02 modifies the `upcoming_fetch_schedule` method signature and its cache key
- Plan 04 modifies the `record_stats_metrics` private method only
- These are disjoint code regions within the same file. To be safe, Plan 04 should modify `record_stats_metrics` by appending lines (not restructuring), making merge trivial.

No overlap with Plan 01 (paginator, shared partial, application_helper) or Plan 03 (sources controller/index).
