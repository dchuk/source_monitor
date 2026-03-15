---
phase: 7
plan: 01
title: Model Correctness & Data Integrity
status: complete
started_at: 2026-03-14
completed_at: 2026-03-14
commits:
  - d0d1d76
  - bb67e7d
  - c8a67ae
  - 7955e4c
  - c5eb60c
tasks_completed: 5
tasks_total: 5
tests_before: 1680
tests_after: 1680
test_failures: 0
rubocop_offenses: 0
deviations:
  - code: DEVN-01
    description: "Leftover sync_log_entry method in scrape_log.rb was removed but landed in wrong commit (21dadcb) due to accidental --amend. Functionally correct."
---

## What Was Built

- LogCleanupJob now deletes LogEntry records before FetchLog/ScrapeLog batch deletions, preventing orphaned polymorphic records
- Source model gains HEALTH_STATUS_VALUES constant and inclusion validation; DB default aligned from "healthy" to "working" via migration
- Source gains scraping_enabled/scraping_disabled scopes
- Item gains restore! method as symmetric counterpart to soft_delete!, maintaining counter cache correctness
- sync_log_entry callback consolidated into Loggable concern, removing duplication from FetchLog, ScrapeLog, HealthCheckLog
- ItemContent uses delegation for feed content access instead of reaching through association
- ImportHistory gains JSONB attribute declarations with proper defaults and chronological validation

## Files Modified

- `app/jobs/source_monitor/log_cleanup_job.rb` -- cascade LogEntry deletes before log record deletes
- `app/models/source_monitor/source.rb` -- HEALTH_STATUS_VALUES, inclusion validation, scraping scopes
- `app/models/source_monitor/item.rb` -- restore! method with counter cache increment
- `app/models/concerns/source_monitor/loggable.rb` -- consolidated sync_log_entry callback
- `app/models/source_monitor/fetch_log.rb` -- removed duplicate sync_log_entry
- `app/models/source_monitor/scrape_log.rb` -- removed duplicate sync_log_entry
- `app/models/source_monitor/health_check_log.rb` -- removed duplicate sync_log_entry
- `app/models/source_monitor/item_content.rb` -- delegate :content to :item with feed prefix
- `app/models/source_monitor/import_history.rb` -- JSONB attribute defaults, chronological validation
- `db/migrate/20260314120000_align_health_status_default.rb` -- change DB default to "working"
- `test/jobs/source_monitor/log_cleanup_job_test.rb` -- orphan prevention tests
- `test/models/source_monitor/source_test.rb` -- health_status validation and scraping scope tests
- `test/models/source_monitor/item_test.rb` -- restore! and counter cache symmetry tests
- `test/models/source_monitor/fetch_log_test.rb` -- sync_log_entry via Loggable test
- `test/models/source_monitor/import_history_test.rb` -- new: JSONB defaults, counts, chronological validation
- `test/dummy/db/schema.rb` -- updated by migration
