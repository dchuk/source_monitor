---
phase: "04"
plan: "02"
title: "Error Classification, Deadlock Rescue & Dead Code Cleanup"
status: complete
tasks_completed: 5
tasks_total: 5
test_runs: 1491
test_assertions: 4537
test_failures: 0
rubocop_offenses: 0
---

## What Was Built

- Transient vs fatal error classification in FaviconFetchJob and DownloadContentImagesJob
- TRANSIENT_ERRORS constant (Timeout::Error, Errno::ETIMEDOUT, Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout, Net::ReadTimeout) in both jobs
- Transient errors re-raise for framework retry; fatal errors handled gracefully
- Per-image fatal errors in DownloadContentImagesJob log at warn level with image URL
- rescue_from ActiveRecord::Deadlocked with jitter retry added to ScrapeItemJob, ItemCleanupJob, LogCleanupJob, ScheduleFetchesJob
- ScrapeItemJob log levels fixed: error stages use :error level, normal stages use :info

## Commits

- `554f8cd` test(04-02): add error classification tests for FaviconFetchJob and DownloadContentImagesJob
- `19bb3b8` feat(04-02): add transient vs fatal error classification to FaviconFetchJob
- `6bcd0ac` feat(04-02): add transient vs fatal error classification to DownloadContentImagesJob
- `911c17e` fix(04-02): add deadlock rescue to 4 jobs, fix ScrapeItemJob log levels

## Tasks Completed

1. Write tests for error classification (TDD red) -- 4 new tests across 2 files
2. Implement error classification in FaviconFetchJob -- TRANSIENT_ERRORS constant, separate rescue clause
3. Implement error classification in DownloadContentImagesJob -- TRANSIENT_ERRORS, per-image warn logging
4. Deadlock rescue + log level fixes -- rescue_from added to 4 jobs, ScrapeItemJob log level dynamic dispatch
5. Verify -- 1491 runs, 4537 assertions, 0 failures; 465 files, 0 RuboCop offenses

## Files Modified

- `app/jobs/source_monitor/favicon_fetch_job.rb` -- TRANSIENT_ERRORS constant, transient rescue clause, log_transient_error method
- `app/jobs/source_monitor/download_content_images_job.rb` -- TRANSIENT_ERRORS constant, transient rescue in per-image loop, log_image_error method
- `app/jobs/source_monitor/scrape_item_job.rb` -- rescue_from Deadlocked, dynamic log level
- `app/jobs/source_monitor/item_cleanup_job.rb` -- rescue_from Deadlocked with jitter retry
- `app/jobs/source_monitor/log_cleanup_job.rb` -- rescue_from Deadlocked with jitter retry
- `app/jobs/source_monitor/schedule_fetches_job.rb` -- rescue_from Deadlocked with jitter retry
- `app/jobs/source_monitor/import_session_health_check_job.rb` -- clarified inline rescue comment
- `test/jobs/source_monitor/favicon_fetch_job_test.rb` -- 2 new tests (transient re-raise, fatal handling)
- `test/jobs/source_monitor/download_content_images_job_test.rb` -- 2 new tests (transient re-raise, per-image skip)

## Deviations

- DEVN-01: ImportSessionHealthCheckJob inline `rescue ActiveRecord::Deadlocked; raise` was NOT dead code as the plan stated. It prevents `rescue StandardError` from swallowing deadlocks before `rescue_from` can catch them. Retained with clarified comment instead of removing.
