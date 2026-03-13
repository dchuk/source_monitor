---
phase: "03"
plan: "02"
title: "Dashboard Schedule Refactor with AR Scopes"
status: complete
---

# Plan 02 Summary: Dashboard Schedule Refactor with AR Scopes

## What Was Built

Replaced in-memory Ruby grouping in `UpcomingFetchSchedule` with per-bucket ActiveRecord scope queries. Each schedule bucket now runs its own scoped query with independent pagination. Turbo Frames wrap each bucket for independent page navigation.

## Tasks Completed

1. **Refactor UpcomingFetchSchedule to use AR scopes** -- Replaced full-table load with per-bucket `WHERE next_fetch_at` range queries. Empty buckets excluded via `.exists?`.
2. **Update DashboardController to pass bucket page params** -- Extracts `schedule_pages` from params, passes to UpcomingFetchSchedule.
3. **Update fetch_schedule partial with Turbo Frames** -- Each bucket wrapped in `turbo_frame_tag` with per-bucket Previous/Next pagination controls.
4. **Update Dashboard::Queries to pass pages param** -- Forwards pages to UpcomingFetchSchedule, includes pages in cache key.
5. **Write tests for refactored UpcomingFetchSchedule** -- 7 new tests covering bucket assignment, empty bucket hiding, pagination, unscheduled sources, and per-bucket page params.

## Files Modified

- `lib/source_monitor/dashboard/upcoming_fetch_schedule.rb` -- Replaced in-memory grouping with AR scope queries
- `app/controllers/source_monitor/dashboard_controller.rb` -- Added schedule_pages param extraction
- `app/views/source_monitor/dashboard/_fetch_schedule.html.erb` -- Added Turbo Frames and per-bucket pagination
- `lib/source_monitor/dashboard/queries.rb` -- Forward pages param, updated cache key
- `test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb` -- NEW: 7 tests

## Commits

- `7aaee56` refactor(dashboard): replace in-memory schedule grouping with AR scope-based bucket queries
- `37d4e86` feat(dashboard): pass per-bucket schedule page params from controller to view
- `81139a5` feat(dashboard): add Turbo Frames and per-bucket pagination to fetch schedule
- `bdb45d4` feat(dashboard): forward pages param through Queries to UpcomingFetchSchedule
- `8f857d9` test(dashboard): add comprehensive tests for AR scope-based fetch schedule

## Deviations

None.

## Test Results

All dashboard tests pass (7 new + existing), 0 failures.
