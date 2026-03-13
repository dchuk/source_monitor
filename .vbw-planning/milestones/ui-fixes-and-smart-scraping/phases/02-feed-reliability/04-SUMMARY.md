---
phase: "02"
plan: "04"
title: "Auto-Pause by Consecutive Failures"
status: complete
---

# Plan 04 Summary: Auto-Pause by Consecutive Failures

## What Was Built

Added a `consecutive_fetch_failures` counter to Source that tracks consecutive fetch failures and automatically pauses sources after 5 consecutive failures. The counter resets on any successful fetch (200 or 304). When auto-pause triggers, the source is paused with `update_columns` (fast, no callbacks), a fetch log entry records the event, and a toast notification is broadcast to the UI.

## Tasks Completed

1. **Migration**: Added `consecutive_fetch_failures` integer column (default 0, NOT NULL) with partial index on `sourcemon_sources`
2. **Counter logic in SourceUpdater**: Reset to 0 on success/304, increment on failure
3. **Auto-pause trigger**: `check_consecutive_failure_auto_pause!` fires after 5 consecutive failures, sets `auto_paused_until`, `auto_paused_at`, `health_status`, `backoff_until`, `next_fetch_at`
4. **Notification**: Creates fetch log entry with `error_class: "SourceMonitor::AutoPause"` and broadcasts warning toast
5. **SourceHealthMonitor integration**: Resume path clears `consecutive_fetch_failures` to 0
6. **Tests**: 11 new tests (10 in `consecutive_failures_test.rb`, 1 in `source_health_monitor_test.rb`)

## Files Modified

- `db/migrate/20260307120000_add_consecutive_fetch_failures_to_sources.rb` (created)
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` (modified)
- `lib/source_monitor/health/source_health_monitor.rb` (modified)
- `test/lib/source_monitor/fetching/consecutive_failures_test.rb` (created)
- `test/lib/source_monitor/health/source_health_monitor_test.rb` (modified)
- `test/dummy/db/schema.rb` (auto-updated by migration)

## Commits

- `1ab10db` feat(migration): add consecutive_fetch_failures column to sources
- `310f95d` feat(fetching): add consecutive failure counter and auto-pause trigger
- `da55bb8` feat(health): reset consecutive_fetch_failures on health monitor resume
- `114cf91` test(fetching): add tests for consecutive failure auto-pause

## Deviations

- **Notification approach**: Used `fetch_logs.create!` instead of `LogEntry.create!` for the auto-pause notification. LogEntry uses delegated_type and requires a loggable (FetchLog/ScrapeLog/HealthCheckLog), so creating a fetch_log entry directly was simpler and consistent with the existing pattern. The fetch log entry uses `error_class: "SourceMonitor::AutoPause"` to distinguish auto-pause events from actual fetch failures.
- **No source_updater_test.rb modifications**: The plan suggested modifying a `source_updater_test.rb` file, but that file doesn't exist. The existing tests are split across `source_updater_error_category_test.rb` and `source_updater_favicon_test.rb`. The new `consecutive_failures_test.rb` comprehensively covers all SourceUpdater counter behavior.

## Validation

- `bin/rubocop` on all modified files: 0 offenses
- `bin/rails test`: 1325 runs, 4022 assertions, 0 failures, 0 errors
