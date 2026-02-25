---
phase: 6
plan: 1
title: Error Handling Safety Net
status: complete
commit: d75365d
tasks_completed: 4
tasks_total: 4
deviations: none
---

## What Was Built

- Split rescue in `update_source_state!` so DB update errors propagate as exceptions while broadcast failures are logged and swallowed
- Added `ensure` block to `FetchRunner#run` that resets `fetch_status` from "fetching" to "failed" on any exit path
- Added per-item `begin/rescue` in `FollowUpHandler#call` so a single enqueue failure doesn't block other items or `mark_complete!`
- 5 new tests covering: DB error propagation, broadcast error swallowing, ensure status reset, partial enqueue failure resilience, full enqueue failure resilience

## Files Modified

- `lib/source_monitor/fetching/fetch_runner.rb` -- split rescue in `update_source_state!`, added ensure block to `#run`
- `lib/source_monitor/fetching/completion/follow_up_handler.rb` -- added per-item rescue in `#call`
- `test/lib/source_monitor/fetching/fetch_runner_test.rb` -- 3 new tests for error handling
- `test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb` -- new file, 2 tests
