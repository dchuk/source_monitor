---
phase: "04"
plan: "02"
title: "Error Classification, Deadlock Rescue & Dead Code Cleanup"
wave: 1
depends_on: []
skills_used:
  - sm-job
  - tdd-cycle
must_haves:
  - "FaviconFetchJob classifies transient errors (Timeout::Error, Errno::ETIMEDOUT, Faraday::TimeoutError, Faraday::ConnectionFailed) separately from fatal errors"
  - "FaviconFetchJob transient errors re-raise to let job framework retry; fatal errors call record_failed_attempt"
  - "DownloadContentImagesJob distinguishes transient errors (timeout/connection) from per-image fatal errors"
  - "DownloadContentImagesJob transient errors re-raise entire job; fatal per-image errors skip with warning log"
  - "ImportSessionHealthCheckJob dead rescue block (unreachable ActiveRecord::Deadlocked rescue) removed"
  - "ScrapeItemJob, ItemCleanupJob, LogCleanupJob, ScheduleFetchesJob have rescue_from ActiveRecord::Deadlocked with jitter retry"
  - "ScrapeItemJob error logging uses warn/error level (not info) for failure paths"
  - "Tests cover transient vs fatal error paths in FaviconFetchJob and DownloadContentImagesJob"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 02: Error Classification, Deadlock Rescue & Dead Code Cleanup

## Objective

Add transient vs fatal error classification to FaviconFetchJob and DownloadContentImagesJob (S6), add deadlock rescue to jobs that lack it, remove dead code from ImportSessionHealthCheckJob (S1), and fix ScrapeItemJob log levels (S5 partial).

## Context

- @.claude/skills/sm-job/SKILL.md -- Job conventions, error handling patterns, deadlock rescue template
- @.claude/skills/tdd-cycle/SKILL.md -- TDD workflow
- FaviconFetchJob (73 lines) catches all StandardError the same way -- timeouts should retry, invalid images should not
- DownloadContentImagesJob (75 lines) silently swallows all errors per-image -- blob/attachment failures should re-raise
- ImportSessionHealthCheckJob has unreachable `rescue ActiveRecord::Deadlocked; raise` at lines 58-59 (rescue_from at line 13 catches first)
- ScrapeItemJob logs errors at `info` level instead of `warn`/`error`
- 4 jobs missing `rescue_from ActiveRecord::Deadlocked`: ScheduleFetchesJob, ItemCleanupJob, LogCleanupJob, ScrapeItemJob

## Tasks

### Task 1: Write tests for error classification (TDD red)

Create/update test files:
- `test/jobs/source_monitor/favicon_fetch_job_test.rb`: test transient error (Faraday::TimeoutError) re-raises; test fatal error (RuntimeError) calls record_failed_attempt without re-raising
- `test/jobs/source_monitor/download_content_images_job_test.rb`: test transient error (Faraday::TimeoutError) re-raises entire job; test per-image fatal error (URI::InvalidURIError) skips image and continues

### Task 2: Implement error classification in FaviconFetchJob

Modify `app/jobs/source_monitor/favicon_fetch_job.rb`:
- Add `TRANSIENT_ERRORS` constant: `[Timeout::Error, Errno::ETIMEDOUT, Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout, Net::ReadTimeout].freeze`
- Add rescue clause for `*TRANSIENT_ERRORS` BEFORE the `StandardError` rescue
- Transient: log at warn level, re-raise (let framework retry)
- Fatal: existing behavior (record_failed_attempt + log_error)

### Task 3: Implement error classification in DownloadContentImagesJob

Modify `app/jobs/source_monitor/download_content_images_job.rb`:
- Add same `TRANSIENT_ERRORS` constant
- In the per-image loop: rescue `*TRANSIENT_ERRORS` and re-raise (abort entire job for retry)
- Keep existing `rescue StandardError` for per-image fatal errors but add `warn`-level logging with image URL
- Ensure `ActiveRecord::Deadlocked` rescue remains above both

### Task 4: Deadlock rescue + dead code cleanup + log level fixes

Apply to multiple jobs:
- **ImportSessionHealthCheckJob**: remove dead `rescue ActiveRecord::Deadlocked; raise` block at lines 58-59
- **ScrapeItemJob**: add `rescue_from ActiveRecord::Deadlocked` with jitter retry; change error log level from `info` to `warn`/`error`
- **ItemCleanupJob**: add `rescue_from ActiveRecord::Deadlocked` with jitter retry
- **LogCleanupJob**: add `rescue_from ActiveRecord::Deadlocked` with jitter retry
- **ScheduleFetchesJob**: add `rescue_from ActiveRecord::Deadlocked` with jitter retry

### Task 5: Verify

- `bin/rails test test/jobs/source_monitor/` -- all job tests pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
- `grep -r "rescue ActiveRecord::Deadlocked" app/jobs/` confirms all jobs have rescue_from or inline rescue
