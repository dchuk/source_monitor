---
phase: 6
plan: 4
title: Queue Separation -- Maintenance Queue
wave: 1
depends_on: []
must_haves:
  - "Configuration has maintenance_queue_name attr_accessor defaulting to 'source_monitor_maintenance'"
  - "Configuration has maintenance_queue_concurrency attr_accessor defaulting to 1"
  - "queue_name_for(:maintenance) returns the configured maintenance queue name with prefix"
  - "concurrency_for(:maintenance) returns the configured maintenance queue concurrency"
  - "FetchFeedJob and ScheduleFetchesJob remain on :fetch queue"
  - "ScrapeItemJob remains on :scrape queue"
  - "SourceHealthCheckJob, ImportSessionHealthCheckJob, ImportOpmlJob, LogCleanupJob, ItemCleanupJob, FaviconFetchJob, DownloadContentImagesJob all use :maintenance queue"
  - "example solid_queue.yml includes source_monitor_maintenance queue"
  - "all existing job tests pass, new tests verify queue assignments"
  - "RuboCop zero offenses on changed files"
skills_used:
  - sm-job
  - sm-configuration-setting
---

## Objective

Add a third "maintenance" queue for non-fetch jobs so the fetch queue is dedicated to FetchFeedJob + ScheduleFetchesJob only. This prevents slow maintenance operations (cleanup, favicon, images, health check, import) from competing for fetch queue slots. REQ-FT-09, REQ-FT-10.

## Context

- `@` `lib/source_monitor/configuration.rb` -- `queue_name_for` (line 60-79) and `concurrency_for` (line 81-90) currently support :fetch and :scrape roles only
- `@` `app/jobs/source_monitor/application_job.rb` -- `source_monitor_queue` helper delegates to `SourceMonitor.queue_name(role)`
- `@` `app/jobs/source_monitor/fetch_feed_job.rb` -- `source_monitor_queue :fetch` (stays)
- `@` `app/jobs/source_monitor/schedule_fetches_job.rb` -- `source_monitor_queue :fetch` (stays)
- `@` `app/jobs/source_monitor/scrape_item_job.rb` -- `source_monitor_queue :scrape` (stays)
- `@` `app/jobs/source_monitor/source_health_check_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/import_session_health_check_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/import_opml_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/log_cleanup_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/item_cleanup_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/favicon_fetch_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `app/jobs/source_monitor/download_content_images_job.rb` -- `source_monitor_queue :fetch` (change to :maintenance)
- `@` `examples/advanced_host/files/config/solid_queue.yml` -- needs maintenance queue entry
- `@` `test/lib/source_monitor/configuration_test.rb` -- existing configuration tests

## Tasks

### 06-04-T1: Add maintenance queue configuration

**Files:** `lib/source_monitor/configuration.rb`

Add `maintenance_queue_name` to `attr_accessor` (default: `"#{DEFAULT_QUEUE_NAMESPACE}_maintenance"`). Add `maintenance_queue_concurrency` to `attr_accessor` (default: 1 -- conservative for small servers). Extend `queue_name_for` to handle `:maintenance` role. Extend `concurrency_for` to handle `:maintenance` role.

**Acceptance:** `SourceMonitor.config.maintenance_queue_name` returns `"source_monitor_maintenance"`. `SourceMonitor.config.queue_name_for(:maintenance)` returns the name with any ActiveJob prefix. `SourceMonitor.config.concurrency_for(:maintenance)` returns 1.

### 06-04-T2: Move non-fetch jobs to maintenance queue

**Files:** `app/jobs/source_monitor/source_health_check_job.rb`, `app/jobs/source_monitor/import_session_health_check_job.rb`, `app/jobs/source_monitor/import_opml_job.rb`, `app/jobs/source_monitor/log_cleanup_job.rb`, `app/jobs/source_monitor/item_cleanup_job.rb`, `app/jobs/source_monitor/favicon_fetch_job.rb`, `app/jobs/source_monitor/download_content_images_job.rb`

Change `source_monitor_queue :fetch` to `source_monitor_queue :maintenance` in all 7 job files. This is a one-line change per file.

**Acceptance:** `grep -r 'source_monitor_queue :fetch' app/jobs/` returns only `fetch_feed_job.rb` and `schedule_fetches_job.rb`. All 7 other jobs show `source_monitor_queue :maintenance`.

### 06-04-T3: Update example Solid Queue config

**Files:** `examples/advanced_host/files/config/solid_queue.yml`

Add `source_monitor_maintenance` queue entry with `concurrency: 1` (matching the conservative default). Add a comment explaining the three queue roles.

**Acceptance:** Example config shows three SourceMonitor queues: fetch, scrape, maintenance.

### 06-04-T4: Write tests for queue separation

**Files:** `test/lib/source_monitor/configuration_test.rb`

Add tests: (1) "maintenance_queue_name defaults to source_monitor_maintenance", (2) "queue_name_for(:maintenance) returns maintenance queue name", (3) "concurrency_for(:maintenance) returns maintenance queue concurrency", (4) "maintenance_queue_name is configurable", (5) "queue_name_for raises for unknown role" (ensure :maintenance doesn't break existing error for truly unknown roles). Also add a test that verifies each job class resolves to the expected queue: fetch jobs → fetch queue, maintenance jobs → maintenance queue, scrape jobs → scrape queue.

**Acceptance:** All tests pass. `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0.

## Verification

```bash
bin/rails test test/lib/source_monitor/configuration_test.rb
bin/rubocop lib/source_monitor/configuration.rb app/jobs/source_monitor/*.rb examples/advanced_host/files/config/solid_queue.yml
```

## Success Criteria

- Non-fetch jobs (7 jobs) use maintenance queue
- Fetch queue dedicated to FetchFeedJob + ScheduleFetchesJob only
- Scrape queue unchanged (ScrapeItemJob)
- `config.maintenance_queue_name` setting exists with default "source_monitor_maintenance"
- `config.maintenance_queue_concurrency` defaults to 1 (small server friendly)
- Example Solid Queue config updated with three SourceMonitor queues
- All existing tests pass, new tests verify queue assignments
- RuboCop zero offenses
