---
phase: "05"
plan: "05"
title: "Test Suite Updates"
wave: 3
depends_on: ["01", "02", "03", "04"]
must_haves:
  - "All tests pass with new health status values"
  - "No references to removed statuses (healthy, warning, critical, auto_paused, unknown) in test assertions"
  - "SourceHealthMonitor tests validate the simplified 4-status decision tree"
  - "SourceHealthReset tests use 'working' instead of 'healthy'"
---

# Plan 05: Test Suite Updates

## Goal
Update all test files to use the new 4-status health vocabulary and verify the simplified decision tree.

## Tasks

### Task 1: Update SourceHealthMonitor tests
**Files:** `test/lib/source_monitor/health/source_health_monitor_test.rb`

This is the most critical test file. Update all assertions:
- Replace `"healthy"` assertions with `"working"`
- Replace `"warning"` assertions with `"failing"` or `"declining"` depending on context
- Replace `"critical"` assertions with `"failing"`
- Remove `"auto_paused"` health status assertions (auto-pause tests should verify `auto_paused_until` is set, not health_status)
- Remove `"unknown"` assertions
- Verify the simplified decision tree: working (rate >= 0.8), failing (rate < auto_pause), declining (3+ consecutive failures OR fallback), improving (2+ successes after failure)

### Task 2: Update SourceHealthReset and health reset controller tests
**Files:** `test/lib/source_monitor/health/source_health_reset_test.rb`, `test/controllers/source_monitor/source_health_resets_controller_test.rb`

- Change all `"healthy"` status assertions to `"working"` in reset tests
- Update any setup that creates sources with old status values

### Task 3: Update Source model, controller, and helper tests
**Files:** `test/models/source_monitor/source_test.rb`, `test/controllers/source_monitor/sources_controller_test.rb`, `test/helpers/source_monitor/application_helper_test.rb`

- Update default health_status assertions from `"healthy"` to `"working"`
- Update any filter tests that use old status values
- Update helper tests for badge mapping and interactive status checks

### Task 4: Update remaining test files with hardcoded status strings
**Files:** `test/lib/source_monitor/dashboard/stats_query_test.rb`, `test/lib/source_monitor/fetching/consecutive_failures_test.rb`, `test/lib/source_monitor/fetching/blocked_error_test.rb`, `test/lib/source_monitor/fetching/feed_fetcher/source_updater_error_category_test.rb`, `test/jobs/source_monitor/source_health_check_job_test.rb`, `test/controllers/source_monitor/source_retries_controller_test.rb`, `test/controllers/source_monitor/import_sessions_controller_test.rb`, `test/system/sources_test.rb`, `test/lib/source_monitor/configuration/scraper_registry_test.rb`

Search each file for `"healthy"`, `"warning"`, `"critical"`, `"auto_paused"`, `"unknown"` and update:
- `"healthy"` -> `"working"` in health_status context
- `"warning"` -> `"declining"` or `"failing"` depending on context
- `"critical"` -> `"failing"`
- `"auto_paused"` -> ensure tests verify `auto_paused_until` rather than health_status
- `"unknown"` -> `"working"` or remove

### Task 5: Run full test suite and fix any remaining failures
**Files:** (none -- shell commands)

Run `PARALLEL_WORKERS=1 bin/rails test` and fix any remaining test failures caused by the status value changes. Also run `bin/rubocop` and `bin/brakeman --no-pager` to verify no new issues.
