---
phase: 6
plan: 4
title: Queue Separation -- Maintenance Queue
status: complete
commit: 8f1f169
tasks_completed: 4
tasks_total: 4
deviations: none
pre_existing_issues:
  - "RuboCop treats examples/advanced_host/files/config/solid_queue.yml as Ruby (YAML syntax errors) -- pre-existing, not caused by changes"
---

## What Was Built

Added dedicated maintenance queue for non-fetch jobs, keeping the fetch queue reserved for FetchFeedJob and ScheduleFetchesJob only. Configuration supports `maintenance_queue_name` (default: `source_monitor_maintenance`) and `maintenance_queue_concurrency` (default: 1, conservative for small servers). Seven jobs moved from `:fetch` to `:maintenance` queue. Tests verify all queue assignments.

## Files Modified

- `lib/source_monitor/configuration.rb` -- added maintenance_queue_name, maintenance_queue_concurrency attrs; extended queue_name_for/concurrency_for
- `app/jobs/source_monitor/source_health_check_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/import_session_health_check_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/import_opml_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/log_cleanup_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/item_cleanup_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/favicon_fetch_job.rb` -- :fetch -> :maintenance
- `app/jobs/source_monitor/download_content_images_job.rb` -- :fetch -> :maintenance
- `examples/advanced_host/files/config/solid_queue.yml` -- added maintenance queue entry with comments
- `test/lib/source_monitor/configuration_test.rb` -- 10 new tests for queue separation
