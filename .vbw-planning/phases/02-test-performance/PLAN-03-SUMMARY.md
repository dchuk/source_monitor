---
phase: 2
plan: 3
status: complete
---
# Plan 03 Summary: Adopt before_all in DB-Heavy Test Files

## Tasks Completed
- [x] Task 1: Convert sources_index_metrics_test.rb to setup_once (17 read-only tests)
- [x] Task 2: Convert 3 single-test files to setup_once for consistency
- [x] Task 3: Verify all converted files individually (PARALLEL_WORKERS=1)
- [x] Task 4: Full suite verification (1033 tests, 0 failures) and lint (0 offenses)

## Commits
- 912665f: perf(02-03): adopt setup_once/before_all in DB-heavy test files

## Files Modified
- test/lib/source_monitor/analytics/sources_index_metrics_test.rb (modified)
- test/lib/source_monitor/analytics/source_activity_rates_test.rb (modified)
- test/lib/source_monitor/analytics/source_fetch_interval_distribution_test.rb (modified)
- test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb (modified)

## What Was Built
- Converted `sources_index_metrics_test.rb` from per-test setup to `setup_once` for shared fixture creation (3 sources + 3 items), following the reference pattern from `query_test.rb` (store IDs in setup_once, re-find records in per-test setup)
- Kept `travel_to`/`travel_back` in regular setup/teardown for thread-local time safety
- Converted 3 single-test files to `setup_once` for `clean_source_monitor_tables!` (functionally identical for single-test classes but normalizes the pattern)
- `setup_once` usage increased from 1 file to 5 files across the test suite

## Deviations
- None
