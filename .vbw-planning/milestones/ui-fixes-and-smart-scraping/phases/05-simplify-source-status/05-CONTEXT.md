# Phase 05: Simplify Source Status — Context

Gathered: 2026-03-11
Calibration: architect

## Phase Boundary
Simplify the source status/health system by separating operational state (active/paused) from health diagnosis (working/declining/improving/failing). Reduce 7 health statuses to 4, fix auto-pause masking health diagnosis, and update all UI/filters/tests.

## Decisions

### Migration Strategy (7 → 4 Health Statuses)
- Direct rename approach: healthy→working, warning+critical→failing, declining stays, improving stays
- auto_paused removed from health_status — it's an operational concern, not a health diagnosis
- pending/unhealthy in import contexts: map pending→working (new sources start healthy), unhealthy→failing
- Data migration required: UPDATE sources SET health_status = 'working' WHERE health_status = 'healthy', etc.

### Two-Axis Model Design
- No new schema columns — operational state already encoded via `active` boolean + `auto_paused_until` timestamp
- health_status column stores ONLY health values: working, declining, improving, failing
- Operational state derived from existing columns: active? && !auto_paused? = "active", !active? = "paused", auto_paused? = "auto-paused"
- Filters updated: "Active" filter excludes auto-paused sources (currently includes them)

### Auto-Pause + Health Interaction
- Auto-paused sources continue receiving health checks on a slow cadence (every 24h)
- health_status updates independently of pause state — a source can be "failing AND auto-paused"
- This provides visibility into whether a paused source has recovered before manual unpausing
- SourceHealthMonitor.determine_status no longer short-circuits to "auto_paused" — evaluates health first, pause is a separate axis
- Implementation: auto-paused sources get next_fetch_at set to 24h intervals for health probe fetches

### Health Transition Rules (Simplified Decision Tree)
- New determine_status logic (evaluated in order):
  1. rate >= healthy_threshold → working
  2. rate < auto_pause_threshold → failing
  3. consecutive_failures >= 3 → declining
  4. improving_streak? (2+ successes after failure) → improving
  5. Fallback (between thresholds, no streak) → declining
- warning_threshold config setting removed entirely
- healthy_threshold and auto_pause_threshold remain as the two boundary points

### Open (Claude's discretion)
- Health badge colors: working=green, declining=yellow, improving=blue, failing=red
- Import session health_status values: new imports default to "working" instead of "pending"
- SourceHealthReset behavior: reset should set health_status to "working" (was "healthy")

## Deferred Ideas
None captured.
