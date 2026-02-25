---
phase: 6
plan: 1
title: Error Handling Safety Net
wave: 1
depends_on: []
must_haves:
  - "update_source_state! rescues broadcast errors separately from DB errors -- DB failures propagate as exceptions"
  - "FetchRunner#run has an ensure block that resets fetch_status from 'fetching' to 'failed' if still 'fetching' on any exit path"
  - "FollowUpHandler#call rescues StandardError around each enqueue so failures don't prevent mark_complete!"
  - "grep -n 'rescue.*StandardError' fetch_runner.rb shows two separate rescue blocks (one for broadcast, one for run)"
  - "test covers: DB update failure in update_source_state! raises, broadcast failure is swallowed, ensure resets fetching status, follow_up_handler error doesn't block completion"
  - "all existing fetch_runner and scheduler tests pass"
  - "RuboCop zero offenses on changed files"
skills_used: []
---

## Objective

Fix three error handling bugs in the fetch pipeline that cause sources to get stuck in "fetching" status: (1) `update_source_state!` swallows ALL errors including DB failures, (2) no ensure block guarantees fetch_status reset, (3) `FollowUpHandler` exceptions propagate past `mark_complete!`. REQ-FT-01, REQ-FT-02, REQ-FT-03.

## Context

- `@` `lib/source_monitor/fetching/fetch_runner.rb` -- `update_source_state!` (line 83-91) rescues ALL StandardError; `#run` (line 49-72) has no ensure block
- `@` `lib/source_monitor/fetching/completion/follow_up_handler.rb` -- `#call` (line 13-21) has no error handling; exceptions propagate up to FetchRunner
- `@` `test/lib/source_monitor/fetching/fetch_runner_test.rb` -- existing tests for status lifecycle, concurrency, retry
- `@` `lib/source_monitor/realtime/broadcaster.rb` -- broadcast_source called from update_source_state!

## Tasks

### 06-01-T1: Split rescue in update_source_state!

**Files:** `lib/source_monitor/fetching/fetch_runner.rb`

Split the single `rescue StandardError` in `update_source_state!` into two steps: (1) call `source.update!(attrs)` without rescue -- let DB errors propagate, (2) wrap only `Realtime.broadcast_source(source)` in a begin/rescue that logs and swallows broadcast failures. This ensures DB update failures (e.g., connection lost, validation error) are never silently swallowed while broadcast failures (non-critical) remain isolated.

**Acceptance:** `update_source_state!` has two separate blocks -- `source.update!(attrs)` is NOT inside a rescue; `Realtime.broadcast_source` IS inside a rescue.

### 06-01-T2: Add ensure block to FetchRunner#run

**Files:** `lib/source_monitor/fetching/fetch_runner.rb`

Add an `ensure` block to `FetchRunner#run` that checks if `source.reload.fetch_status == "fetching"` and if so, resets it to `"failed"`. This is a safety net for unexpected exits (e.g., Timeout::Error, thread kill, unknown exceptions). The ensure should NOT rescue errors from the check itself -- wrap the ensure body in its own begin/rescue to avoid masking the original exception. The ensure runs after the existing `rescue StandardError => error` block, so it only activates if `mark_failed!` somehow didn't run or if a non-StandardError exception occurred.

**Acceptance:** `FetchRunner#run` method has an `ensure` block. After any exit path (success, failure, unexpected exception), `source.fetch_status` is never left as `"fetching"`.

### 06-01-T3: Add rescue in FollowUpHandler#call

**Files:** `lib/source_monitor/fetching/completion/follow_up_handler.rb`

Wrap the `each` loop body in `FollowUpHandler#call` with a begin/rescue StandardError that logs the error and continues to the next item. This ensures a single scrape enqueue failure doesn't prevent other items from being enqueued or block the caller (`FetchRunner`) from reaching `mark_complete!`. Log format: `[SourceMonitor] FollowUpHandler: failed to enqueue scrape for item #{item.id}: #{error.class}: #{error.message}`.

**Acceptance:** `FollowUpHandler#call` contains a rescue block. A single item enqueue failure doesn't raise out of `#call`.

### 06-01-T4: Write tests for error handling changes

**Files:** `test/lib/source_monitor/fetching/fetch_runner_test.rb`, `test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb` (new file)

Add to fetch_runner_test.rb: (1) test that DB update failure in update_source_state! propagates (stub source.update! to raise ActiveRecord::ConnectionNotEstablished, verify it raises), (2) test that broadcast failure is swallowed (stub Realtime.broadcast_source to raise, verify source still updates), (3) test that ensure block resets fetch_status from "fetching" when an unexpected error occurs inside the lock block.

Create follow_up_handler_test.rb: (1) test that a single enqueue failure doesn't prevent other items from being enqueued, (2) test that #call completes without raising even when enqueue raises.

**Acceptance:** All new tests pass. `bin/rails test test/lib/source_monitor/fetching/fetch_runner_test.rb test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb` exits 0.

## Verification

```bash
bin/rails test test/lib/source_monitor/fetching/fetch_runner_test.rb test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb
bin/rubocop lib/source_monitor/fetching/fetch_runner.rb lib/source_monitor/fetching/completion/follow_up_handler.rb
```

## Success Criteria

- DB update failures in fetch_status transitions raise instead of being silently swallowed
- Broadcast failures are still rescued (non-critical)
- FetchRunner always resets fetch_status from "fetching" via ensure block
- FollowUpHandler errors don't prevent source status from being updated
- All existing tests pass, new tests cover all three error handling changes
- RuboCop zero offenses
