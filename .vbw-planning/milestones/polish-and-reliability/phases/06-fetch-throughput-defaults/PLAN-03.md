---
phase: 6
plan: 3
title: Scheduler Config Exposure
wave: 1
depends_on: []
must_haves:
  - "FetchingSettings has scheduler_batch_size attr_accessor with default 25"
  - "FetchingSettings has stale_timeout_minutes attr_accessor with default 5"
  - "Scheduler.run reads batch size from SourceMonitor.config.fetching.scheduler_batch_size instead of DEFAULT_BATCH_SIZE constant"
  - "Scheduler uses stale_timeout from config instead of STALE_QUEUE_TIMEOUT constant"
  - "StalledFetchReconciler.default_stale_after reads from config instead of Scheduler constant"
  - "host apps can override via SourceMonitor.configure { |c| c.fetching.scheduler_batch_size = 50 }"
  - "all existing scheduler tests pass, new tests verify configurable defaults"
  - "RuboCop zero offenses on changed files"
skills_used:
  - sm-configuration-setting
---

## Objective

Replace hardcoded `DEFAULT_BATCH_SIZE = 100` and `STALE_QUEUE_TIMEOUT = 10.minutes` in Scheduler with configurable settings in FetchingSettings, optimized for 1-CPU/2GB servers (batch_size=25, stale_timeout=5min). REQ-FT-06, REQ-FT-07.

## Context

- `@` `lib/source_monitor/scheduler.rb` -- `DEFAULT_BATCH_SIZE = 100` (line 8), `STALE_QUEUE_TIMEOUT = 10.minutes` (line 9); used in `self.run` (line 12) and `fetch_status_predicate` (line 75-77)
- `@` `lib/source_monitor/configuration/fetching_settings.rb` -- existing settings with `reset!` pattern; add new attrs here
- `@` `lib/source_monitor/fetching/stalled_fetch_reconciler.rb` -- `default_stale_after` (line 45-51) references `Scheduler::STALE_QUEUE_TIMEOUT`
- `@` `test/lib/source_monitor/scheduler_test.rb` -- existing tests reference `STALE_QUEUE_TIMEOUT` constant
- `@` `.claude/skills/sm-configuration-setting/SKILL.md` -- pattern for adding config settings

## Tasks

### 06-03-T1: Add scheduler settings to FetchingSettings

**Files:** `lib/source_monitor/configuration/fetching_settings.rb`

Add two new `attr_accessor` fields: `scheduler_batch_size` (default: 25) and `stale_timeout_minutes` (default: 5). Set defaults in `reset!`. These follow the existing pattern of the other FetchingSettings attributes.

**Acceptance:** `SourceMonitor.config.fetching.scheduler_batch_size` returns 25 by default. `SourceMonitor.config.fetching.stale_timeout_minutes` returns 5 by default. Both are settable via `SourceMonitor.configure { |c| c.fetching.scheduler_batch_size = 50 }`.

### 06-03-T2: Wire Scheduler to read from config

**Files:** `lib/source_monitor/scheduler.rb`

Change `self.run` to read batch size from config: `limit: SourceMonitor.config.fetching.scheduler_batch_size` as the default instead of `DEFAULT_BATCH_SIZE`. Keep `DEFAULT_BATCH_SIZE` constant as a fallback (used if config not yet initialized), but mark it with a comment as legacy. For stale timeout: add a private method `stale_timeout` that reads `SourceMonitor.config.fetching.stale_timeout_minutes.minutes` and use it in place of `STALE_QUEUE_TIMEOUT` in `run` (line 23) and `fetch_status_predicate` (line 75-77). Keep `STALE_QUEUE_TIMEOUT` constant as legacy fallback.

**Acceptance:** `Scheduler.run` uses `config.fetching.scheduler_batch_size` for the limit parameter. `fetch_status_predicate` uses the configured stale timeout. Changing the config value changes scheduler behavior.

### 06-03-T3: Update StalledFetchReconciler to use config

**Files:** `lib/source_monitor/fetching/stalled_fetch_reconciler.rb`

Update `default_stale_after` (line 45-51) to read from `SourceMonitor.config.fetching.stale_timeout_minutes.minutes` instead of `Scheduler::STALE_QUEUE_TIMEOUT`. Keep the fallback to `10.minutes` if config is not available.

**Acceptance:** `StalledFetchReconciler.call` uses the configured stale timeout by default. Scheduler and reconciler use the same timeout value from the same config source.

### 06-03-T4: Write tests for configurable scheduler settings

**Files:** `test/lib/source_monitor/scheduler_test.rb`

Add tests: (1) "scheduler uses configured batch size" -- set `config.fetching.scheduler_batch_size = 2`, create 5 due sources, verify only 2 enqueued. (2) "scheduler uses configured stale timeout" -- set `config.fetching.stale_timeout_minutes = 3`, create queued source stale for 4 minutes, verify it gets re-enqueued. (3) "default batch size is 25" -- verify `SourceMonitor.config.fetching.scheduler_batch_size == 25` after reset. (4) "default stale timeout is 5 minutes" -- verify `SourceMonitor.config.fetching.stale_timeout_minutes == 5`. Update existing tests that reference `STALE_QUEUE_TIMEOUT` constant to also work with the new default (5 min instead of 10).

**Acceptance:** All new and existing scheduler tests pass. `bin/rails test test/lib/source_monitor/scheduler_test.rb` exits 0.

## Verification

```bash
bin/rails test test/lib/source_monitor/scheduler_test.rb
bin/rubocop lib/source_monitor/scheduler.rb lib/source_monitor/configuration/fetching_settings.rb lib/source_monitor/fetching/stalled_fetch_reconciler.rb
```

## Success Criteria

- Scheduler batch size configurable, defaults to 25
- Stale queue timeout configurable, defaults to 5 minutes
- StalledFetchReconciler uses same configured timeout
- Host apps can override both via standard configure DSL
- All existing scheduler tests pass (may need timeout value updates for new 5-min default)
- New tests verify configurable behavior
- RuboCop zero offenses
