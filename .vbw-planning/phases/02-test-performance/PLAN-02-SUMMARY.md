---
plan: "02"
phase: "02"
title: "Log Level Reduction and Integration Test Tagging"
status: complete
commits:
  - hash: edbfe23
    message: "perf(02-02): reduce test log IO and add test:fast rake task"
tasks_completed: 4
tasks_total: 4
files_modified:
  - test/dummy/config/environments/test.rb
files_created:
  - lib/tasks/test_fast.rake
---

## What Was Built

- Set `config.log_level = :warn` in test environment to eliminate ~95MB of debug log IO per test run
- Created `lib/tasks/test_fast.rake` providing `test:fast` rake task that excludes integration/ and system/ directories
- Verified all 4 integration test files already in `test/integration/` (no moves needed)
- Full suite: 1033 runs, 0 failures; Fast mode: 1022 runs, 0 failures

## Files Modified

- `test/dummy/config/environments/test.rb` — added `config.log_level = :warn` after `config.cache_store = :null_store`
- `lib/tasks/test_fast.rake` — new rake task `test:fast` using Dir glob to exclude integration and system test files

## Deviations

- Plan specified `--exclude-pattern` flag for minitest but this flag does not exist in Rails/Minitest. Replaced with Dir glob approach that rejects `test/integration/` and `test/system/` paths (DEVN-01 Minor).
- Also excluded `test/system/` from fast mode since `bin/rails test` already excludes system tests by default — this makes `test:fast` equivalent to `bin/rails test` minus integration tests.
- Rake task accessible as `bundle exec rake app:test:fast` from engine root (engine prefixes with `app:`).
