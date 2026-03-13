---
phase: "03"
type: research
title: "Dashboard Pagination Research"
date: 2026-03-07
---

# Phase 03 Research: Dashboard Pagination

## Findings

### Dashboard Schedule (Current State)
- `UpcomingFetchSchedule` (127 lines) loads ALL active sources into memory, groups by fetch window in Ruby
- 5 buckets: 0-30 min, 30-60 min, 60-120 min, 120-240 min, 240+ min
- `DashboardController#index` calls `Dashboard::Queries` which caches results per-request
- Dashboard view renders `_fetch_schedule.html.erb` partial with grouped data
- No pagination or limits on schedule data — all active sources loaded

### Existing Paginator
- `Pagination::Paginator` (91 lines) at `lib/source_monitor/pagination/paginator.rb`
- Result struct: `records, page, per_page, has_next_page, has_previous_page`
- Offset-based: fetches `(page-1)*per_page + 1` records to detect next page
- Does NOT track total count or total pages — only has_next/has_previous
- Supports both ActiveRecord::Relation and Array scopes
- Default: 25/page, max: 100/page
- Needs modification to add `total_count` and `total_pages` for jump-to-page

### Sources Index Pagination
- Controller uses `Paginator.new(scope: @q.result, page: params[:page], per_page: params[:per_page])`
- View renders prev/next buttons at bottom within `source_monitor_sources_table` Turbo Frame
- Preserves search params and per_page across pagination links
- No page number display, no jump-to-page, no total count shown

### Dashboard Stats
- `StatsQuery` computes: total sources, active sources, failed sources, total items, fetches today
- Health status distribution NOT currently computed — needs new query
- `Source` model has `health_status` column with values: healthy, warning, declining, critical

### Source Model Scopes
- `Source.active` scope exists (where active: true)
- `health_status` is a string column — can group by it
- `next_fetch_at` is a datetime column — can use range queries for schedule buckets
- No existing scope for fetch window bucketing

### Turbo Frame Usage
- Sources index wrapped in `turbo_frame_tag "source_monitor_sources_table"`
- Dashboard uses Turbo Cable broadcasts for real-time updates
- Schedule section does NOT use Turbo Frames currently — needs frames for independent pagination

### N+1 Prevention
- Sources index pre-computes avg word counts, activity rates via GROUP BY queries
- Dashboard schedule currently loads source objects directly — minimal associations

## Relevant Patterns

1. **Paginator reuse**: Extend existing `Paginator` with optional `total_count` / `total_pages` — backward compatible
2. **AR scope per bucket**: `Source.active.where(next_fetch_at: now..now+30.minutes)` for each window
3. **Turbo Frame per section**: Each schedule bucket in its own frame for independent pagination
4. **Health distribution**: `Source.active.group(:health_status).count` — single SQL query
5. **Pagination partial**: Extract shared partial from sources index, reuse in dashboard schedule sections
6. **Empty bucket hiding**: Conditional render only when bucket scope has records

## Risks

1. **Paginator total_count**: Adding `COUNT(*)` adds a second query per paginated section. For 5 schedule sections + 1 sources index = 6 count queries. Mitigate: count query is cheap on indexed columns.
2. **Dashboard query explosion**: 5 independent schedule sections × 2 queries each (data + count) = 10 queries vs current 1. Mitigate: all are simple indexed WHERE on next_fetch_at.
3. **Turbo Frame state**: Independent pagination per section means multiple page params. Need namespaced params (e.g., `schedule_0_30_page=2`).
4. **Schedule section ordering**: With DB-level pagination, need to ensure consistent ordering within each bucket.

## Recommendations

1. **Extend Paginator first**: Add optional `include_total: true` flag to compute total pages. Keep backward compatible.
2. **Create schedule bucket scopes**: Add class method or scope on Source for each fetch window.
3. **Extract pagination partial**: Share between sources index and dashboard schedule.
4. **Add health distribution query**: Simple `group(:health_status).count` to StatsQuery.
5. **Use Turbo Frames**: One frame per schedule section for independent lazy pagination.
6. **Test with volume**: Create system test with 100+ sources to verify performance.
