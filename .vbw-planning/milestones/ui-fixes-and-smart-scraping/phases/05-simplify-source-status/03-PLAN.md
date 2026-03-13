---
phase: "05"
plan: "03"
title: "Simplify SourceHealthMonitor and SourceHealthReset"
wave: 2
depends_on: ["01", "02"]
must_haves:
  - "determine_status returns only: working, declining, improving, failing"
  - "auto_paused no longer short-circuits health diagnosis"
  - "warning_threshold reference removed from SourceHealthMonitor"
  - "SourceHealthReset resets to 'working' instead of 'healthy'"
---

# Plan 03: Simplify SourceHealthMonitor and SourceHealthReset

## Goal
Rewrite the `determine_status` decision tree to produce only 4 health values and decouple auto-pause from health diagnosis. Update SourceHealthReset to use the new default status.

## Tasks

### Task 1: Rewrite determine_status in SourceHealthMonitor
**Files:** `lib/source_monitor/health/source_health_monitor.rb`

Replace the current `determine_status` method with the simplified decision tree:
1. `rate >= healthy_threshold` -> `"working"`
2. `rate < auto_pause_threshold` -> `"failing"`
3. `consecutive_failures(logs) >= 3` -> `"declining"`
4. `improving_streak?(logs)` -> `"improving"`
5. Fallback (between thresholds, no streak) -> `"declining"`

Remove the `auto_paused_active?` check from `determine_status` -- auto-pause is an operational concern handled separately by the auto-pause logic already in `call`.

Remove the `warning_threshold` method entirely. Update `healthy_threshold` to no longer reference `warning_threshold`.

Update `apply_status` fallback from `"healthy"` to `"working"`.

### Task 2: Update SourceHealthReset default status
**Files:** `lib/source_monitor/health/source_health_reset.rb`

Change `health_status: "healthy"` to `health_status: "working"` in `reset_attributes`.

### Task 3: Update ImportSourceHealthCheck status values
**Files:** `lib/source_monitor/health/import_source_health_check.rb`

Change `"healthy"` to `"working"` and `"unhealthy"` to `"failing"` in the Result structs. This aligns the import wizard health check with the new status vocabulary.
