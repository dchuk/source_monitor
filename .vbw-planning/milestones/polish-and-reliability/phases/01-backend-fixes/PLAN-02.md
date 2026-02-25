---
phase: 1
plan: 2
title: "Health Check Status Transition"
wave: 1
depends_on: []
must_haves:
  - Successful health check on degraded source enqueues FetchFeedJob.perform_later(source.id, force: true)
  - Degraded defined as health_status in %w[declining critical warning]
  - Healthy/improving/auto_paused sources do NOT trigger extra fetch
  - Failed health checks do NOT trigger extra fetch
  - New tests verify fetch enqueued for declining source after success
  - New tests verify fetch NOT enqueued for healthy source after success
  - New tests verify fetch NOT enqueued after failed health check
  - bin/rails test passes, bin/rubocop zero offenses
---

# Plan 02: Health Check Status Transition

## Objective

After a successful manual health check on a degraded source, enqueue a full feed fetch so SourceHealthMonitor can naturally transition the source's health_status.

## Context

- `@app/jobs/source_monitor/source_health_check_job.rb` -- perform, broadcast_outcome (lines 9-24)
- `@lib/source_monitor/health/source_health_check.rb` -- call, Result struct
- `@app/jobs/source_monitor/fetch_feed_job.rb` -- perform(source_id, force: true) bypasses should_run?
- `@lib/source_monitor/health/source_health_monitor.rb` -- runs via after_fetch_completed callback
- `@test/jobs/source_monitor/source_health_check_job_test.rb` -- 5 existing tests

REQ-HC-01: After a successful manual health check on a declining/critical/warning source, trigger re-evaluation.

**Decision:** Hybrid approach -- enqueue `FetchFeedJob.perform_later(source.id, force: true)` after successful health check on degraded source. The full fetch creates a real fetch_log, letting SourceHealthMonitor handle status transitions naturally.

## Tasks

### Task 1: Add fetch trigger to SourceHealthCheckJob

**Files:** `app/jobs/source_monitor/source_health_check_job.rb`

In the `perform` method, after `broadcast_outcome(source, result)` and before `result`:

```ruby
trigger_fetch_if_degraded(source, result)
```

Add private method:

```ruby
DEGRADED_STATUSES = %w[declining critical warning].freeze

def trigger_fetch_if_degraded(source, result)
  return unless result&.success?
  return unless DEGRADED_STATUSES.include?(source.health_status.to_s)

  SourceMonitor::FetchFeedJob.perform_later(source.id, force: true)
end
```

This keeps the logic contained in the job. No changes to SourceHealthCheck or SourceHealthMonitor.

### Task 2: Add tests for fetch trigger on degraded sources

**Files:** `test/jobs/source_monitor/source_health_check_job_test.rb`

Add tests using `assert_enqueued_with` and `ActiveJob::TestHelper`:

1. **"enqueues fetch when health check succeeds on declining source"**
   - Create source with `health_status: "declining"`, stub successful HTTP response
   - `perform_enqueued_jobs(only: SourceMonitor::SourceHealthCheckJob)`
   - Assert `FetchFeedJob` enqueued with `[source.id, { force: true }]`

2. **"enqueues fetch when health check succeeds on critical source"**
   - Same pattern with `health_status: "critical"`

3. **"enqueues fetch when health check succeeds on warning source"**
   - Same pattern with `health_status: "warning"`

4. **"does not enqueue fetch when health check succeeds on healthy source"**
   - Create source with `health_status: "healthy"`, stub successful response
   - Assert no `FetchFeedJob` enqueued

5. **"does not enqueue fetch when health check fails on degraded source"**
   - Create source with `health_status: "declining"`, stub timeout
   - Assert no `FetchFeedJob` enqueued

## Files

| Action | Path |
|--------|------|
| MODIFY | `app/jobs/source_monitor/source_health_check_job.rb` |
| MODIFY | `test/jobs/source_monitor/source_health_check_job_test.rb` |

## Verification

```bash
bin/rails test test/jobs/source_monitor/source_health_check_job_test.rb
bin/rubocop app/jobs/source_monitor/source_health_check_job.rb
```

## Success Criteria

- Successful health check on declining/critical/warning source enqueues FetchFeedJob with force: true
- Healthy/improving/auto_paused sources skip the extra fetch
- Failed health checks never trigger extra fetch
- Existing health check tests still pass unchanged
- Zero RuboCop offenses
