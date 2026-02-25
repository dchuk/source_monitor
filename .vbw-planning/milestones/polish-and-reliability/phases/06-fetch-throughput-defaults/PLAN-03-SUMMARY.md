---
phase: 6
plan: 3
title: Scheduler Config Exposure
status: complete
commit: f612340
tasks_completed: 4
tasks_total: 4
files_modified: 4
deviations: 0
---

## What Was Built

- `scheduler_batch_size` (default 25) and `stale_timeout_minutes` (default 5) added to FetchingSettings
- Scheduler.run reads batch size and stale timeout from config instead of hardcoded constants
- StalledFetchReconciler.default_stale_after reads from config with fallback
- 4 new tests + existing tests updated for 5-min default; 16 tests pass, 0 failures

## Files Modified

- `lib/source_monitor/configuration/fetching_settings.rb` — added 2 attr_accessors + defaults
- `lib/source_monitor/scheduler.rb` — wired to config, added stale_timeout method
- `lib/source_monitor/fetching/stalled_fetch_reconciler.rb` — reads config instead of Scheduler constant
- `test/lib/source_monitor/scheduler_test.rb` — 4 new tests, updated constant refs
