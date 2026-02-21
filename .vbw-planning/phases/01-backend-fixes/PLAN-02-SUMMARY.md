---
phase: 1
plan: 2
title: "Health Check Status Transition"
status: complete
tasks: 2
commits:
  - e502f1c
  - 4df9725
tests_before: 5
tests_after: 10
deviations: none
---

## What Was Built

- Added `trigger_fetch_if_degraded` to `SourceHealthCheckJob` that enqueues `FetchFeedJob.perform_later(source.id, force: true)` after a successful health check on a degraded source (declining/critical/warning)
- Added 5 tests covering all degraded statuses, healthy source exclusion, and failed health check exclusion

## Files Modified

- `app/jobs/source_monitor/source_health_check_job.rb` -- added DEGRADED_STATUSES constant, trigger_fetch_if_degraded private method, call in perform
- `test/jobs/source_monitor/source_health_check_job_test.rb` -- 5 new test cases (10 total, 46 assertions, 0 failures)
