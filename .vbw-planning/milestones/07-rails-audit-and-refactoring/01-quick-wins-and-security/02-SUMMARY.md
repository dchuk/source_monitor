---
phase: "01"
plan: "02"
title: "Model & Job Fixes"
status: complete
---
## What Was Built
Added missing query scopes to ScrapeLog (by_source, by_status, by_item) and ImportSession (in_step). Fixed hardcoded table name in Source.avg_word_count and replaced update_columns with Rails-native reset_counters in reset_items_counter!. Improved job error handling: deadlock retry for ImportSessionHealthCheckJob, removed implicit return values from SourceHealthCheckJob, and added error logging to ScheduleFetchesJob.

## Commits
- 00a6618 feat: add missing scopes to ScrapeLog and ImportSession
- ac0c204 fix(models): replace hardcoded table name in Source.avg_word_count and improve reset_items_counter!
- 2fc5675 fix(jobs): add deadlock rescue, remove explicit returns, add error logging

## Tasks Completed
- Task 1: Added by_source, by_status, by_item scopes to ScrapeLog and in_step scope to ImportSession with tests
- Task 2: Replaced hardcoded 'sourcemon_item_contents' with ItemContent.table_name in Source.avg_word_count; replaced update_columns with Rails-native reset_counters in reset_items_counter!
- Task 3: Skipped (plan self-identified LogEntry.recent scope as not a duplicate — it is independent, not inherited from Loggable)
- Task 4: Added rescue_from ActiveRecord::Deadlocked to ImportSessionHealthCheckJob with retry; removed explicit result/nil returns from SourceHealthCheckJob; added error logging with re-raise to ScheduleFetchesJob

## Files Modified
- app/models/source_monitor/scrape_log.rb
- app/models/source_monitor/import_session.rb
- app/models/source_monitor/source.rb
- app/jobs/source_monitor/import_session_health_check_job.rb
- app/jobs/source_monitor/source_health_check_job.rb
- app/jobs/source_monitor/schedule_fetches_job.rb
- test/models/source_monitor/scrape_log_test.rb
- test/models/source_monitor/import_session_test.rb
- test/jobs/source_monitor/import_session_health_check_job_test.rb
- test/jobs/source_monitor/schedule_fetches_job_test.rb

## Deviations
- Task 2: Plan specified update! for reset_items_counter!, but update! cannot modify counter_cache columns (Rails ignores them). Used Rails-native Source.reset_counters instead, which is the idiomatic approach for counter cache resets.
- Task 3: No changes made — plan self-identified the LogEntry.recent scope as intentional and not a duplicate.
- First commit message missing scope prefix (feat: instead of feat(models):) — corrected in subsequent commits.
