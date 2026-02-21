---
phase: "02"
plan: "03"
title: "Adopt before_all in DB-Heavy Test Files"
wave: 1
depends_on: []
must_haves:
  - "REQ-PERF-05: Top DB-heavy test files converted from per-test setup to setup_once/before_all"
  - "sources_index_metrics_test.rb converted to setup_once (17 tests, shared read-only fixtures)"
  - "Additional eligible files converted where safe (read-only shared data)"
  - "Only read-only test data shared via setup_once (tests that mutate data keep per-test setup)"
  - "All converted tests pass individually with PARALLEL_WORKERS=1"
  - "Full test suite passes with no isolation regressions"
  - "RuboCop zero offenses on modified files"
skills_used: []
---

# Plan 03: Adopt before_all in DB-Heavy Test Files

## Objective

Convert eligible DB-heavy test files from per-test `setup` to `setup_once`/`before_all` for shared fixture creation. The `setup_once` helper (alias for `before_all`) is already wired up in `test/test_prof.rb` but only used in 1 of 54 eligible files. This saves ~3-5s by eliminating redundant database INSERT/DELETE cycles.

## Context

- `@` `test/test_prof.rb` -- `setup_once` (alias for `before_all`) already configured and included in `ActiveSupport::TestCase`
- `@` `test/lib/source_monitor/logs/query_test.rb` -- only existing user of `setup_once` (reference pattern)
- `@` `test/lib/source_monitor/analytics/sources_index_metrics_test.rb` -- 17 tests, shared read-only fixtures. **PRIMARY candidate: creates 3 sources + 3 items in setup, all tests only query this data.**
- `@` `test/lib/source_monitor/analytics/source_activity_rates_test.rb` -- 1 test, uses `clean_source_monitor_tables!`
- `@` `test/lib/source_monitor/analytics/source_fetch_interval_distribution_test.rb` -- 1 test, uses `clean_source_monitor_tables!`
- `@` `test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb` -- 1 test, uses `clean_source_monitor_tables!`

**Safety analysis performed:**
- `sources_index_metrics_test.rb`: SAFE. All 17 tests construct `SourcesIndexMetrics.new(...)` and call read-only query methods. No test creates, updates, or deletes records.
- `source_activity_rates_test.rb`: SAFE but minimal benefit (1 test, setup runs once either way).
- `source_fetch_interval_distribution_test.rb`: SAFE but minimal benefit (1 test).
- `upcoming_fetch_schedule_test.rb`: SAFE but minimal benefit (1 test).
- `dashboard/queries_test.rb`: NOT SAFE. Each test creates its own sources and checks specific counts. Shared state would cause pollution.
- `health/source_health_monitor_test.rb`: NOT SAFE. Tests mutate `@source` via `SourceHealthMonitor.call`.
- `items/item_creator_test.rb`: NOT SAFE. Tests create items on shared source and check counts.

**Rationale:** `before_all` wraps fixture creation in a SAVEPOINT, shared across all tests in the class. After all tests run, the savepoint rolls back. This only works when tests are read-only on the shared data. The `sources_index_metrics_test.rb` is the highest-value candidate with 17 read-only tests sharing the same 3 sources + 3 items.

## Tasks

### Task 1: Convert sources_index_metrics_test.rb to setup_once (PRIMARY)

This is the highest-impact conversion. Convert `test/lib/source_monitor/analytics/sources_index_metrics_test.rb`:

Replace:
```ruby
setup do
  clean_source_monitor_tables!
  travel_to Time.current.change(usec: 0)
  @fast_source = create_source!(name: "Fast", fetch_interval_minutes: 30)
  # ... fixture creation
end
```

With:
```ruby
setup_once do
  clean_source_monitor_tables!
  @fast_source = create_source!(name: "Fast", fetch_interval_minutes: 30)
  # ... same fixture creation, but now runs once for all 17 tests
end
```

**Important:** The `travel_to` call must stay in a regular `setup` block because `travel_to` affects the thread-local time for each test independently:
```ruby
setup_once do
  clean_source_monitor_tables!
  # fixture creation here
end

setup do
  travel_to Time.current.change(usec: 0)
end

teardown do
  travel_back
end
```

Wait -- `travel_to` inside `setup_once` would freeze time for the SAVEPOINT transaction but tests need consistent time for assertions. Actually, the fixtures are created with relative timestamps (`1.day.ago`, `2.days.ago`) which depend on `Time.current`. If `travel_to` is in `setup_once`, the timestamps are fixed at creation time, which is fine since tests read them as-is. But `travel_back` in teardown would only run once after all tests, and the `travel_to` in `setup_once` persists through all tests.

Safest approach: Move `travel_to` into `setup_once` and remove the teardown's `travel_back` (before_all handles cleanup). Add a regular `setup` with `travel_to` at the same frozen time to ensure each test sees consistent time.

Actually, the simplest safe approach: keep `travel_to` and `travel_back` in regular `setup`/`teardown`, and only put the DB operations in `setup_once`. The fixtures use relative timestamps (`1.day.ago`) which will be slightly different each test, but since the tests only compare relative values (bucket labels, activity rates), this is fine.

### Task 2: Convert single-test analytics files to setup_once

Convert these 3 files for consistency (minimal performance benefit but establishes the pattern):

1. **`test/lib/source_monitor/analytics/source_activity_rates_test.rb`** -- Replace `setup { clean_source_monitor_tables! }` with `setup_once { clean_source_monitor_tables! }`
2. **`test/lib/source_monitor/analytics/source_fetch_interval_distribution_test.rb`** -- Same pattern
3. **`test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb`** -- Same pattern

For single-test classes, `setup` and `setup_once` are functionally identical, so this is a no-op in terms of performance but normalizes the codebase to use the `setup_once` pattern for table cleaning.

### Task 3: Verify all converted files individually

Run each converted file with PARALLEL_WORKERS=1 to confirm no regressions:
```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/analytics/sources_index_metrics_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/analytics/source_activity_rates_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/analytics/source_fetch_interval_distribution_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb
```

If any file fails due to test isolation issues, revert it to per-test setup and document why.

### Task 4: Full suite verification and lint

```bash
# Full suite (all 1031+ tests pass)
bin/rails test

# Lint all modified files
bin/rubocop test/lib/source_monitor/analytics/ test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb
```

Ensure total test count remains 1031+ and no failures occur.

## Files

| Action | Path |
|--------|------|
| MODIFY | `test/lib/source_monitor/analytics/sources_index_metrics_test.rb` |
| MODIFY | `test/lib/source_monitor/analytics/source_activity_rates_test.rb` |
| MODIFY | `test/lib/source_monitor/analytics/source_fetch_interval_distribution_test.rb` |
| MODIFY | `test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb` |

## Verification

```bash
# Individual file runs
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/analytics/sources_index_metrics_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb

# Full suite (all 1031+ tests pass)
bin/rails test

# Lint
bin/rubocop test/lib/source_monitor/analytics/ test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb
```

## Success Criteria

- `grep -r "setup_once" test/lib/source_monitor/` shows 5+ files (up from 1)
- `sources_index_metrics_test.rb` uses `setup_once` for fixture creation
- All 1031+ tests pass in full suite
- No test isolation regressions in parallel runs
- Each converted file passes individually with PARALLEL_WORKERS=1
