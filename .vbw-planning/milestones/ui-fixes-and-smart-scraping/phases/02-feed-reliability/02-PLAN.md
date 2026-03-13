---
phase: "02"
plan: "02"
title: "Force-Fetch Lock Contention Handling"
wave: 1
depends_on: []
must_haves:
  - "Force-fetch skips immediately when advisory lock is busy (no retries)"
  - "User sees 'Fetch already in progress' toast message"
  - "Scheduled fetches keep existing retry behavior (5 attempts, 30s wait)"
  - "No duplicate jobs stacked for same source"
  - "Tests for force-fetch skip and scheduled retry paths"
---

# Plan 02: Force-Fetch Lock Contention Handling

## Summary

When a user force-fetches a source that is already being fetched (advisory lock busy), the system currently retries 5 times over 2.5 minutes before failing. Instead, force-fetches should fail fast with a clear "Fetch already in progress" message. Scheduled fetches keep the existing retry behavior.

## Tasks

### Task 1: Differentiate force-fetch vs scheduled ConcurrencyError handling in FetchFeedJob

**Files to modify:**
- `app/jobs/source_monitor/fetch_feed_job.rb`

**Steps:**
1. Remove the class-level `retry_on ConcurrencyError` declaration (line 11-13) -- we need conditional behavior
2. Add a `rescue_from ConcurrencyError` block that checks the `force` argument:
   - If `force: true`: log "Fetch already in progress for source #{source_id}", reset fetch_status to previous state (idle or failed), and return without retry. Store the "already in progress" info so the controller can surface it.
   - If `force: false` (scheduled): implement manual retry logic equivalent to the removed `retry_on` -- retry up to 5 times with 30s wait, using `retry_job(wait: 30.seconds)` and tracking attempt count
3. The force-fetch path should update source fetch_status back from "queued" to its previous state (likely "idle" or "fetching") since the fetch didn't actually happen. Use `update_columns(fetch_status: "idle")` since the source is already fetching in another process.

### Task 2: Add pre-enqueue check in FetchRunner.enqueue for force-fetch

**Files to modify:**
- `lib/source_monitor/fetching/fetch_runner.rb`

**Steps:**
1. In `FetchRunner.enqueue`, when `force: true`, check if `source.fetch_status == "fetching"` BEFORE enqueuing the job
2. If already fetching, return a result/value indicating "already in progress" instead of enqueuing -- this avoids even creating the job
3. Return a simple struct or symbol: `{ skipped: true, reason: :already_fetching }` or just `:already_fetching`
4. Keep the existing behavior for non-force (scheduled) enqueues -- they should still enqueue regardless

### Task 3: Update SourceRetriesController to handle "already in progress"

**Files to modify:**
- `app/controllers/source_monitor/source_retries_controller.rb`

**Steps:**
1. Check the return value of `FetchRunner.enqueue`
2. If the source is already fetching, render a warning toast: "Fetch already in progress for this source. Please wait for the current fetch to complete."
3. Use `render_fetch_enqueue_response` with `toast_level: :warning` for this case
4. Keep the existing success path for normal enqueue

### Task 4: Tests

**Files to create:**
- `test/lib/source_monitor/fetching/force_fetch_lock_test.rb`

**Files to modify:**
- `test/jobs/source_monitor/fetch_feed_job_test.rb` (or wherever job tests live)
- `test/controllers/source_monitor/source_retries_controller_test.rb` (or integration test)

**Steps:**
1. **force_fetch_lock_test.rb**: Integration-style test:
   - Test that `FetchRunner.enqueue(source, force: true)` when source.fetch_status == "fetching" returns :already_fetching and does NOT enqueue a job
   - Test that `FetchRunner.enqueue(source, force: true)` when source.fetch_status == "idle" enqueues normally
   - Test that `FetchRunner.enqueue(source, force: false)` always enqueues regardless of status
2. **fetch_feed_job_test.rb**:
   - Test that force-fetch ConcurrencyError does NOT retry (returns immediately)
   - Test that scheduled ConcurrencyError retries up to 5 times
   - Test that force-fetch resets fetch_status to "idle" on ConcurrencyError
3. **source_retries_controller_test.rb**:
   - Test that force-fetching an already-fetching source returns warning toast
   - Test that force-fetching an idle source returns normal success response

## Acceptance Criteria

- [ ] Force-fetching a source that is already being fetched shows "Fetch already in progress" immediately (no 2.5min wait)
- [ ] Scheduled fetches still retry ConcurrencyError 5 times with 30s backoff
- [ ] Source fetch_status is correctly managed (not left in "queued" state when skipped)
- [ ] No duplicate force-fetch jobs are stacked
- [ ] All new code has test coverage
- [ ] `bin/rubocop` passes with zero offenses
- [ ] `bin/rails test` passes
