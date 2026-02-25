---
phase: 6
title: Fetch Throughput & Small Server Defaults
status: complete
total_tests: 4
passed: 4
failed: 0
skipped: 0
started_at: 2026-02-24
completed_at: 2026-02-24
---

## UAT Tests

### P01-T1: Error handling prevents stuck "fetching" sources

**Scenario:** Verify error handling safety net prevents sources from getting permanently stuck in "fetching" status.

**Expected:** DB errors propagate (not swallowed), broadcast errors are rescued, ensure block exists as safety net.

**Result:** PASS
- `update_source_state!` (fetch_runner.rb:90-100): `source.update!(attrs)` is bare (no rescue), broadcast wrapped in begin/rescue
- `run` method (lines 72-78): ensure block reloads source, resets "fetching" to "failed", defensive inner rescue
- `FollowUpHandler#call` (follow_up_handler.rb:19-25): per-item begin/rescue wraps each enqueue call with logging

### P02-T1: Fixed-interval sources get scheduling jitter

**Scenario:** Verify fixed-interval path uses jitter instead of exact intervals.

**Expected:** Fixed-interval path uses `adjusted_interval_with_jitter(fixed_seconds)` for +-10% jitter.

**Result:** PASS
- adaptive_interval.rb lines 31-33: `fixed_seconds = fixed_minutes * 60.0`, then `adjusted_interval_with_jitter(fixed_seconds)` — no longer exact minutes

### P03-T1: Scheduler defaults optimized for small servers

**Scenario:** Verify scheduler defaults are small-server friendly and configurable.

**Expected:** batch_size=25, stale_timeout=5, both configurable via DSL.

**Result:** PASS
- fetching_settings.rb: `@scheduler_batch_size = 25`, `@stale_timeout_minutes = 5` in reset!
- scheduler.rb reads from config with legacy constant fallbacks
- stalled_fetch_reconciler.rb reads from config with 10.minutes fallback

### P04-T1: Maintenance queue separates non-fetch jobs

**Scenario:** Verify queue separation: 7 non-fetch jobs on maintenance, only 2 jobs on fetch.

**Expected:** 3 queues (fetch, scrape, maintenance), proper job assignments, example config updated.

**Result:** PASS
- configuration.rb: `maintenance_queue_name` defaults to "source_monitor_maintenance", concurrency 1
- `queue_name_for(:maintenance)` and `concurrency_for(:maintenance)` both work
- 7 jobs on `:maintenance`: source_health_check, import_session_health_check, import_opml, log_cleanup, item_cleanup, favicon_fetch, download_content_images
- 2 jobs on `:fetch`: fetch_feed, schedule_fetches
- solid_queue.yml has all 3 queues with env var overrides and explanatory comments
