---
phase: "02"
plan: "04"
title: "Auto-Pause by Consecutive Failures"
wave: 2
depends_on: ["01"]
must_haves:
  - "consecutive_fetch_failures counter on Source model"
  - "Counter increments on any fetch failure, resets to 0 on success"
  - "Auto-pause triggers after 5 consecutive failures"
  - "Auto-pause integrates with existing health status system"
  - "User notification via toast + log entry when auto-pause triggers"
  - "Tests for counter increment/reset, auto-pause trigger, and notification"
---

# Plan 04: Auto-Pause by Consecutive Failures

## Summary

Add a `consecutive_fetch_failures` counter to Source. Increment on every failed fetch, reset on success. When counter reaches 5, auto-pause the source. Integrate with the existing health status system and notify the user.

## Tasks

### Task 1: Add consecutive_fetch_failures column to Source

**Files to create:**
- `db/migrate/TIMESTAMP_add_consecutive_fetch_failures_to_sources.rb`

**Steps:**
1. Create migration adding `consecutive_fetch_failures` integer column to `sourcemon_sources`, default: 0, null: false
2. Add index: `add_index :sourcemon_sources, :consecutive_fetch_failures, where: "consecutive_fetch_failures > 0", name: "index_sources_on_consecutive_failures"`

### Task 2: Increment/reset counter in SourceUpdater

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

**Steps:**
1. In `update_source_for_success`: add `consecutive_fetch_failures: 0` to the attributes hash (reset on success)
2. In `update_source_for_not_modified`: add `consecutive_fetch_failures: 0` to the attributes hash (304 is a success)
3. In `update_source_for_failure`: add `consecutive_fetch_failures: source.consecutive_fetch_failures.to_i + 1` to the attrs hash
4. After updating source in `update_source_for_failure`, check if `consecutive_fetch_failures >= 5` and trigger auto-pause if so

### Task 3: Auto-pause trigger on consecutive failure threshold

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

**Steps:**
1. Add private method `check_consecutive_failure_auto_pause!` called after source.update! in `update_source_for_failure`
2. Threshold: 5 consecutive failures (use a constant `CONSECUTIVE_FAILURE_PAUSE_THRESHOLD = 5`)
3. When threshold reached:
   - Set `auto_paused_until` to `Time.current + auto_pause_cooldown` (use config value from `SourceMonitor.config.health.auto_pause_cooldown_minutes`)
   - Set `auto_paused_at` to `Time.current`
   - Set `health_status` to `"auto_paused"`
   - Set `health_status_changed_at` to `Time.current`
   - Set `backoff_until` to match `auto_paused_until`
   - Set `next_fetch_at` to match `auto_paused_until`
   - Use `source.update_columns(...)` for this second update (avoids callbacks, fast)
4. Only trigger if source is not already auto-paused (`auto_paused_until.nil? || auto_paused_until.past?`)

### Task 4: Notification when auto-pause triggers

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

**Steps:**
1. When auto-pause triggers (Task 3), create a LogEntry to record the event:
   - Use `SourceMonitor::LogEntry.create!` with level: "warning", message describing the auto-pause
   - Associate with the source
2. Broadcast a toast notification via the realtime system:
   - Use `SourceMonitor::Realtime.broadcast_toast(message: "Source '#{source.name}' has been auto-paused after #{threshold} consecutive failures.", level: :warning)` if the method exists
   - If no broadcast_toast method, use `SourceMonitor::Realtime.broadcast_source(source)` to update the UI with the new auto_paused status
3. Keep notification simple -- log entry + source broadcast is sufficient

### Task 5: Integration with SourceHealthMonitor

**Files to modify:**
- `lib/source_monitor/health/source_health_monitor.rb`

**Steps:**
1. In `determine_status`, check `consecutive_fetch_failures` as an additional signal:
   - If `source.consecutive_fetch_failures.to_i >= 5` AND source is auto-paused, status is `"auto_paused"` (this should already work since Task 3 sets auto_paused_until)
   - No changes needed if the existing auto_paused_active? check covers it
2. Verify that when health monitor resumes a source (rate recovers), `consecutive_fetch_failures` is also reset
3. In the resume path (`should_resume?`), ensure consecutive_fetch_failures is reset to 0 when auto_paused_until is cleared
4. Add `attrs[:consecutive_fetch_failures] = 0` in the resume block alongside clearing `auto_paused_until`

### Task 6: Tests

**Files to create:**
- `test/lib/source_monitor/fetching/consecutive_failures_test.rb`

**Files to modify:**
- `test/lib/source_monitor/fetching/source_updater_test.rb`
- `test/lib/source_monitor/health/source_health_monitor_test.rb`

**Steps:**
1. **consecutive_failures_test.rb**: Integration test covering the full flow:
   - Test counter increments on failure: source starts at 0, after 1 failure it's 1, after 2 it's 2
   - Test counter resets on success: source at 3 failures, successful fetch resets to 0
   - Test counter resets on 304 not-modified: same reset behavior
   - Test auto-pause triggers at exactly 5: after 5th failure, source.auto_paused_until is set, health_status is "auto_paused"
   - Test auto-pause does NOT trigger at 4: after 4th failure, source is not paused
   - Test auto-pause skips if already paused: source already has auto_paused_until in future, no double-pause
2. **source_updater_test.rb**:
   - Test that consecutive_fetch_failures is included in success attributes (reset)
   - Test that consecutive_fetch_failures is included in failure attributes (increment)
3. **source_health_monitor_test.rb**:
   - Test that resume clears consecutive_fetch_failures
   - Test that auto_paused status is correctly detected when consecutive failures >= 5

## Acceptance Criteria

- [ ] `consecutive_fetch_failures` increments on every fetch failure
- [ ] `consecutive_fetch_failures` resets to 0 on any successful fetch (200 or 304)
- [ ] Source is auto-paused after exactly 5 consecutive failures
- [ ] Auto-pause sets `auto_paused_until`, `health_status`, `backoff_until`, `next_fetch_at`
- [ ] A log entry is created when auto-pause triggers
- [ ] Source UI reflects auto-paused state via existing health status badges
- [ ] Health monitor resume path clears consecutive_fetch_failures
- [ ] Already-paused sources are not double-paused
- [ ] All new code has test coverage
- [ ] `bin/rubocop` passes with zero offenses
- [ ] `bin/rails test` passes
