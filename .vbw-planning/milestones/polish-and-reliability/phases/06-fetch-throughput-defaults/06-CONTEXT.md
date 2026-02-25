# Phase 6: Fetch Throughput & Small Server Defaults — Context

Gathered: 2026-02-24
Calibration: architect

## Phase Boundary

Fix three compounding bugs causing "overdue" jobs on dashboards with hundreds of sources: silent error swallowing in fetch status transitions, missing scheduling jitter/stagger creating thundering herd effects, and hardcoded constants that can't be tuned by host apps. Optimize all defaults for a 1-CPU/2GB server while exposing configuration hooks for scaling up.

## Decisions

### Batch Size vs Recovery Tradeoff
- Small fixed default (25) for scheduler batch size, configurable by host app via `SourceMonitor.configure` DSL (initializer pattern)
- The batch size controls ongoing steady-state throughput (every-minute scheduler cycle), not just OPML import
- Host apps scale up by setting `config.fetching.scheduler_batch_size` in their initializer

### OPML Import Stagger Strategy
- Keep current behavior: all imported sources get NULL next_fetch_at (immediately due)
- The scheduler's batch limit (25) naturally throttles the initial rush
- No staggering needed — the real fix is queue separation so downstream jobs don't block fetch workers

### Queue Separation (emerged from import discussion)
- Split from 2 queues to 3: **fetch** (FetchFeedJob + ScheduleFetchesJob only), **maintenance** (cleanup, favicon, images, health check, import), **scrape** (already exists)
- Fetch workers get 100% dedicated capacity for actual feed fetching
- Downstream jobs spawned by fetches (favicon, image download) go to maintenance queue so they don't compete
- New `config.maintenance_queue_name` setting, defaults follow existing naming pattern

### Error Handling Strictness
- Split rescue + ensure approach for `update_source_state!`
- DB update errors propagate (raise) so Solid Queue retry handles them
- Broadcast errors remain rescued (non-critical, UI-only)
- Add `ensure` block in `FetchRunner#run` that resets fetch_status to "failed" if still "fetching" on any exit path
- Also add rescue in `FollowUpHandler#call` so scrape enqueue failures don't skip `mark_complete!`

### Configuration Surface Area
- Full config exposure: `scheduler_batch_size`, `stale_timeout`, and `maintenance_queue_name` all added to config
- Fix the fixed-interval path to use the existing `jitter_percent` config (currently skips jitter entirely)
- `jitter_percent` already exists in FetchingSettings and is read by AdaptiveInterval — just wire it into the fixed-interval path too
- All new settings live in FetchingSettings (scheduler knobs) or top-level Configuration (queue names)
- Defaults optimized for 1-CPU/2GB: batch_size=25, stale_timeout=5.minutes, concurrency=2

### Open (Claude's discretion)
- Exact placement of new settings in FetchingSettings vs a new SchedulerSettings sub-config
- Whether ScheduleFetchesJob stays in fetch queue or moves to its own scheduler queue (leaning: keep in fetch since it's lightweight and needs to run reliably)
- Test approach for ensure block (likely: mock update! to raise, verify status reset)

## Deferred Ideas
- Adaptive batch sizing (adjusts based on queue depth) — over-engineering for now, revisit if scaling issues persist
- Per-source queue assignment (high-priority sources get dedicated workers) — future enhancement
