---
phase: "02"
plan: "02"
title: "Force-Fetch Lock Contention Handling"
status: complete
---

# Plan 02 Summary: Force-Fetch Lock Contention Handling

## What Was Built

When a user force-fetches a source that is already being fetched, the system now fails fast with a clear "Fetch already in progress" warning toast instead of retrying 5 times over 2.5 minutes. Scheduled fetches retain their existing retry behavior.

The solution works at two levels:
1. **Pre-enqueue check**: `FetchRunner.enqueue` detects `fetch_status == "fetching"` before even creating a job, returning `:already_fetching` immediately
2. **Job-level fallback**: If a force-fetch job does encounter a `ConcurrencyError` (race condition), it skips retries and resets the source status to idle

## Tasks Completed

1. **Task 1: ConcurrencyError handling in FetchFeedJob** (verified existing - commit 47361b2)
   - `rescue_from ConcurrencyError` differentiates force vs scheduled fetches
   - Force: logs skip, resets status to idle, no retry
   - Scheduled: retries up to 5 times with 30s wait

2. **Task 2: Pre-enqueue check in FetchRunner.enqueue** (commit 6ada960)
   - Added early return of `:already_fetching` when `force: true` and source is fetching
   - Prevents duplicate job creation entirely

3. **Task 3: SourceRetriesController warning toast** (commit cfe7016)
   - Checks return value from `FetchRunner.enqueue`
   - Renders warning-level toast: "Fetch already in progress for this source..."

4. **Task 4: Tests** (commit 6731ac5)
   - `force_fetch_lock_test.rb`: 6 tests for FetchRunner pre-enqueue behavior
   - `fetch_feed_job_test.rb`: 3 new tests for force-fetch ConcurrencyError handling
   - `source_retries_controller_test.rb`: 1 new test for warning toast response

## Files Modified

- `lib/source_monitor/fetching/fetch_runner.rb` - pre-enqueue check
- `app/controllers/source_monitor/source_retries_controller.rb` - warning toast handling
- `app/jobs/source_monitor/fetch_feed_job.rb` - (Task 1, pre-existing commit)

## Files Created

- `test/lib/source_monitor/fetching/force_fetch_lock_test.rb` - integration tests

## Files Modified (Tests)

- `test/jobs/source_monitor/fetch_feed_job_test.rb` - force-fetch ConcurrencyError tests
- `test/controllers/source_monitor/source_retries_controller_test.rb` - warning toast test

## Commits

- `47361b2` feat(fetching): handle force-fetch ConcurrencyError without retries (pre-existing)
- `6ada960` feat(fetching): add pre-enqueue check for force-fetch lock contention
- `cfe7016` feat(controller): show warning toast when force-fetch is already in progress
- `6731ac5` test(fetching): add tests for force-fetch lock contention handling

## Deviations

None. All tasks completed as planned.

## Validation

- `bin/rubocop`: 0 offenses on all modified files
- `bin/rails test`: 1257 runs, 3895 assertions, 0 failures, 0 errors, 0 skips
