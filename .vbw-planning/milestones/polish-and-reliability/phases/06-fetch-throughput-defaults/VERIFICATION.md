---
phase: "06-fetch-throughput-defaults"
tier: deep
result: PASS
passed: 37
failed: 1
total: 38
date: "2026-02-24"
---

## Must-Have Checks

| # | ID | Truth/Condition | Status | Evidence |
|---|----|----|--------|---------|
| 1 | MH-01 | update_source_state! rescues broadcast errors separately from DB errors | PASS | `source.update!(attrs)` bare at line 91; broadcast wrapped in `begin/rescue` at lines 92-98 of fetch_runner.rb |
| 2 | MH-02 | DB failures propagate as exceptions from update_source_state! | PASS | `source.update!(attrs)` is NOT inside any rescue block |
| 3 | MH-03 | FetchRunner#run has ensure block that resets fetch_status from 'fetching' to 'failed' | PASS | Lines 72-78: `ensure` block with `source.reload; source.update!(fetch_status: "failed") if source.fetch_status == "fetching"` |
| 4 | MH-04 | FollowUpHandler#call rescues StandardError per-item so failures don't block mark_complete! | PASS | Lines 19-25: `begin/rescue StandardError` wraps each `enqueuer_class.enqueue(...)` call |
| 5 | MH-05 | Two separate rescue blocks in fetch_runner.rb (broadcast + run) | PASS | grep confirms 4 rescue lines: NotAcquiredError, StandardError (run), StandardError (ensure fallback), StandardError (broadcast) |
| 6 | MH-06 | Test: DB update failure in update_source_state! raises | PASS | `fetch_runner_test.rb` line 333: stubs `update!` to raise `ActiveRecord::ConnectionNotEstablished`, asserts raise |
| 7 | MH-07 | Test: broadcast failure is swallowed, source still updates | PASS | `fetch_runner_test.rb` line 357: stubs `broadcast_source` to raise, asserts source reaches "idle" |
| 8 | MH-08 | Test: ensure resets fetch_status from fetching on unexpected error | PASS | `fetch_runner_test.rb` line 376: failing fetcher + assert "failed" status after exception |
| 9 | MH-09 | Test: follow_up_handler partial failure doesn't prevent other items | PASS | `follow_up_handler_test.rb` line 14: `call_count == 2` after first enqueue fails |
| 10 | MH-10 | Test: follow_up_handler complete failure doesn't raise | PASS | `follow_up_handler_test.rb` line 57: `assert_nothing_raised` with always-failing enqueuer |
| 11 | MH-11 | Fixed-interval path uses adjusted_interval_with_jitter, not exact minutes | PASS | Lines 31-33 of adaptive_interval.rb: `fixed_seconds = fixed_minutes * 60.0; attributes[:next_fetch_at] = Time.current + adjusted_interval_with_jitter(fixed_seconds)` |
| 12 | MH-12 | Fixed-interval sources get ±jitter_percent variation on next_fetch_at (default 10%) | PASS | `adjusted_interval_with_jitter` calls `jitter_offset` which reads `jitter_percent_value` (default 0.1) |
| 13 | MH-13 | jitter_proc override still works for fixed-interval path | PASS | `feed_fetcher_adaptive_interval_test.rb` line 225: proc override test passes (9/9 tests) |
| 14 | MH-14 | Existing adaptive interval tests still pass unchanged | PASS | 9 adaptive interval tests pass; existing tests use `jitter: ->(_) { 0 }` override |
| 15 | MH-15 | FetchingSettings has scheduler_batch_size attr_accessor with default 25 | PASS | `fetching_settings.rb` lines 12, 26: `attr_accessor :scheduler_batch_size`; `@scheduler_batch_size = 25` |
| 16 | MH-16 | FetchingSettings has stale_timeout_minutes attr_accessor with default 5 | PASS | `fetching_settings.rb` lines 13, 27: `attr_accessor :stale_timeout_minutes`; `@stale_timeout_minutes = 5` |
| 17 | MH-17 | Scheduler.run reads batch size from config instead of DEFAULT_BATCH_SIZE | PASS | `scheduler.rb` line 12: `def self.run(limit: SourceMonitor.config.fetching.scheduler_batch_size, now: Time.current)` |
| 18 | MH-18 | Scheduler uses stale_timeout from config instead of STALE_QUEUE_TIMEOUT constant | PASS | `scheduler.rb` lines 46-47: `def stale_timeout; SourceMonitor.config.fetching.stale_timeout_minutes.minutes; end` used at lines 23 and 79 |
| 19 | MH-19 | StalledFetchReconciler.default_stale_after reads from config instead of Scheduler constant | PASS | `stalled_fetch_reconciler.rb` line 46: `SourceMonitor.config.fetching.stale_timeout_minutes.minutes` with `rescue NoMethodError` fallback |
| 20 | MH-20 | Host apps can override via SourceMonitor.configure { \|c\| c.fetching.scheduler_batch_size = 50 } | PASS | Confirmed by scheduler_test.rb line 268: sets batch_size=2, verifies only 2 enqueued from 5 sources |
| 21 | MH-21 | All existing scheduler tests pass, new tests verify configurable defaults | PASS | 16 scheduler tests pass (4 new: default_batch_size, default_stale, configurable_batch, configurable_stale) |
| 22 | MH-22 | Configuration has maintenance_queue_name attr_accessor defaulting to 'source_monitor_maintenance' | PASS | `configuration.rb` lines 25, 42: `attr_accessor :maintenance_queue_name`; `@maintenance_queue_name = "#{DEFAULT_QUEUE_NAMESPACE}_maintenance"` |
| 23 | MH-23 | Configuration has maintenance_queue_concurrency attr_accessor defaulting to 1 | PASS | `configuration.rb` lines 28, 45: `@maintenance_queue_concurrency = 1` |
| 24 | MH-24 | queue_name_for(:maintenance) returns configured maintenance queue name with prefix | PASS | `configuration.rb` lines 71-72: `when :maintenance; maintenance_queue_name` |
| 25 | MH-25 | concurrency_for(:maintenance) returns configured maintenance queue concurrency | PASS | `configuration.rb` lines 93-94: `when :maintenance; maintenance_queue_concurrency` |
| 26 | MH-26 | FetchFeedJob and ScheduleFetchesJob remain on :fetch queue | PASS | `grep source_monitor_queue :fetch` returns only these 2 files |
| 27 | MH-27 | ScrapeItemJob remains on :scrape queue | PASS | `scrape_item_job.rb` line 5: `source_monitor_queue :scrape` |
| 28 | MH-28 | 7 jobs use :maintenance queue (SourceHealthCheckJob, ImportSessionHealthCheckJob, ImportOpmlJob, LogCleanupJob, ItemCleanupJob, FaviconFetchJob, DownloadContentImagesJob) | PASS | All 7 job files show `source_monitor_queue :maintenance` |
| 29 | MH-29 | Example solid_queue.yml includes all 3 SourceMonitor queues | PASS | `examples/advanced_host/files/config/solid_queue.yml` contains source_monitor_fetch, source_monitor_scrape, source_monitor_maintenance |
| 30 | MH-30 | All existing job tests pass, new tests verify queue assignments | PASS | configuration_test.rb: 10 new queue separation tests all pass (95/95 total) |

## Artifact Checks

| # | ID | Artifact | Exists | Contains | Status |
|---|----|----|--------|---------|--------|
| 1 | ART-01 | `lib/source_monitor/fetching/fetch_runner.rb` | YES | ensure block + split rescue in update_source_state! | PASS |
| 2 | ART-02 | `lib/source_monitor/fetching/completion/follow_up_handler.rb` | YES | per-item begin/rescue StandardError | PASS |
| 3 | ART-03 | `test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb` | YES | 2 new tests for error resilience | PASS |
| 4 | ART-04 | `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` | YES | fixed-interval else-branch calls adjusted_interval_with_jitter | PASS |
| 5 | ART-05 | `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` | YES | 3 new jitter tests (9 total) | PASS |
| 6 | ART-06 | `lib/source_monitor/configuration/fetching_settings.rb` | YES | scheduler_batch_size=25, stale_timeout_minutes=5 in reset! | PASS |
| 7 | ART-07 | `lib/source_monitor/scheduler.rb` | YES | self.run reads config, stale_timeout method, legacy constants remain as fallbacks | PASS |
| 8 | ART-08 | `lib/source_monitor/fetching/stalled_fetch_reconciler.rb` | YES | default_stale_after reads config with NoMethodError rescue fallback | PASS |
| 9 | ART-09 | `lib/source_monitor/configuration.rb` | YES | maintenance_queue_name, maintenance_queue_concurrency, queue_name_for(:maintenance), concurrency_for(:maintenance) | PASS |
| 10 | ART-10 | `examples/advanced_host/files/config/solid_queue.yml` | YES | 3-queue layout with comments explaining roles | PASS |

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|----|----|--------|---------|
| 1 | AP-01 | Swallowing DB errors in broad rescue in update_source_state! | PASS (fixed) | `source.update!(attrs)` at line 91 is bare — no rescue wrapping it |
| 2 | AP-02 | Missing ensure block leaving source stuck in 'fetching' | PASS (fixed) | ensure block at lines 72-78 of fetch_runner.rb |
| 3 | AP-03 | FollowUpHandler exceptions propagating past mark_complete! | PASS (fixed) | per-item rescue at lines 19-25 of follow_up_handler.rb |
| 4 | AP-04 | Fixed-interval path uses exact minutes without jitter (thundering herd) | PASS (fixed) | `adjusted_interval_with_jitter(fixed_seconds)` at line 33 of adaptive_interval.rb |
| 5 | AP-05 | Hardcoded DEFAULT_BATCH_SIZE=100 in Scheduler.run | PASS (fixed) | Scheduler.run default param now reads config; constant retained as legacy fallback only |
| 6 | AP-06 | STALE_QUEUE_TIMEOUT constant used directly in StalledFetchReconciler | PASS (fixed) | default_stale_after now reads config; constant only remains as legacy in scheduler.rb |
| 7 | AP-07 | Stale constant reference: Scheduler::STALE_QUEUE_TIMEOUT in production code | WARN | `schedule_fetches_job.rb` line 26 still uses `Scheduler::DEFAULT_BATCH_SIZE` as fallback for explicit calls with no options. When ScheduleFetchesJob runs with no args (normal recurring schedule), it passes 100 to Scheduler.run instead of the configured 25. The plan's must_have targets only Scheduler.run's default param — not ScheduleFetchesJob. Legacy constant still present but marked as "legacy fallback". |
| 8 | AP-08 | Test isolation: follow_up_handler_test.rb fails when run standalone | FAIL | Missing `require "source_monitor/fetching/completion/follow_up_handler"` — both tests error with `NameError: uninitialized constant FollowUpHandler` when run in isolation. Full suite passes (1211/0) because the class loads from another test. |
| 9 | AP-09 | No `:nocov:` guard on unreachable rescue in ensure block | PASS | ensure rescue at line 76 correctly annotated with `# :nocov:` |
| 10 | AP-10 | Maintenance queue concurrency inconsistency between config default and example YAML | PASS | Both config default and YAML use concurrency: 1; ENV var override supported in YAML |

## Requirement Mapping

| # | ID | Requirement | Plan Ref | Evidence | Status |
|---|----|----|---------|---------|--------|
| 1 | REQ-01 | REQ-FT-01/02/03: Error handling safety net | PLAN-01 must_haves 1-6 | All 3 changes in fetch_runner.rb + follow_up_handler.rb; 5 new tests | PASS |
| 2 | REQ-02 | REQ-FT-04: Fixed-interval jitter | PLAN-02 must_haves 1-4 | adaptive_interval.rb else-branch wired; 3 new tests pass | PASS |
| 3 | REQ-03 | REQ-FT-06/07: Configurable batch size + stale timeout | PLAN-03 must_haves 1-7 | FetchingSettings new attrs; Scheduler + StalledFetchReconciler wired; 4 new tests | PASS |
| 4 | REQ-04 | REQ-FT-09/10: Maintenance queue separation | PLAN-04 must_haves 1-8 | 7 jobs moved to :maintenance; config updated; example YAML updated; 10 new tests | PASS |
| 5 | REQ-05 | ScheduleFetchesJob uses configured batch size (implied) | Not in PLAN-03 must_haves | ScheduleFetchesJob still uses `DEFAULT_BATCH_SIZE` (100) as fallback — out of plan scope but creates semantic gap | WARN |

## Convention Compliance

| # | ID | Convention | File | Status | Detail |
|---|----|----|------|--------|--------|
| 1 | CON-01 | RuboCop zero offenses | All changed files | PASS | `bin/rubocop` exits 0 across 369 files |
| 2 | CON-02 | Brakeman zero warnings | All files | PASS | 0 security warnings, 1 pre-existing ignored warning |
| 3 | CON-03 | Minitest (no RSpec/FactoryBot) | All test files | PASS | All new tests use ActiveSupport::TestCase, create_source! factory |
| 4 | CON-04 | Configuration reset! pattern in FetchingSettings | `fetching_settings.rb` | PASS | New attrs initialized in reset! following existing pattern |
| 5 | CON-05 | frozen_string_literal header | All new/changed files | PASS | All files include `# frozen_string_literal: true` |
| 6 | CON-06 | Test file requires implementation file | `follow_up_handler_test.rb` | FAIL | Missing `require "source_monitor/fetching/completion/follow_up_handler"` — standalone isolation broken |
| 7 | CON-07 | `:nocov:` annotation on unreachable rescue paths | `fetch_runner.rb` line 76 | PASS | Defensive ensure rescue annotated `# :nocov:` |
| 8 | CON-08 | Shallow jobs (jobs delegate to services, no business logic) | All job files | PASS | Jobs only call source_monitor_queue and delegate to Scheduler/FetchRunner |

## Summary

Tier: deep | Result: PASS | Passed: 37/38 | Failed: [CON-06 / AP-08 — follow_up_handler_test.rb missing require for standalone isolation]

**Full test suite: 1211 runs, 3755 assertions, 0 failures, 0 errors, 0 skips**
**RuboCop: 0 offenses | Brakeman: 0 warnings**

One non-blocking issue found: `test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb` is missing a `require` for its subject class. Both tests in the file fail with `NameError` when run in isolation (`bin/rails test test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb`). They pass in the full suite because `fetch_runner.rb` already requires the class transitively. All must-haves from all 4 plans are satisfied. Core behavior is verified and correct.

One architectural note (WARN, not a failure): `ScheduleFetchesJob#extract_limit` falls back to `Scheduler::DEFAULT_BATCH_SIZE` (100) when called with no explicit `options` argument. In normal recurring schedule operation, this means the job sends limit=100 to Scheduler.run, bypassing the `config.fetching.scheduler_batch_size = 25` default. This was not in scope for PLAN-03 but creates a semantic gap between the configured default and the job-driven default.
