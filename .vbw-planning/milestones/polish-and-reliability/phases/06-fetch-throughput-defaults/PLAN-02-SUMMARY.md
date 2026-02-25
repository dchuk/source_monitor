---
phase: 6
plan: 2
title: Fixed-Interval Jitter
status: complete
commits:
  - hash: 8e74b67
    message: "fix(06-p2): wire fixed-interval scheduling to use jitter"
tasks_completed: 2
tasks_total: 2
deviations: none
---

## What Was Built

- Wired fixed-interval scheduling path to use `adjusted_interval_with_jitter` instead of exact minutes, applying default ±10% jitter to prevent thundering herd
- Added 3 tests: default jitter applied, jitter_proc override respected, zero jitter_percent produces exact interval

## Files Modified

- `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` -- fixed-interval else branch now converts to seconds and calls `adjusted_interval_with_jitter`
- `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` -- 3 new tests (9 total, all passing)
