---
phase: "07"
plan: "03"
title: "Job Shallowness & Pipeline Cleanup"
status: complete
wave: 1
commits: 5
tests_before: 1686
tests_after: 1686
test_failures: 0
rubocop_offenses: 0
---

## What Was Built

- Extracted ImportOpmlJob business logic to ImportSessions::OPMLImporter service (H2, pre-existing from 07-05 agent)
- Extracted ScrapeItemJob to Scraping::Runner, removed duplicate rate-limiting from job (H3+H5)
- Extracted DownloadContentImagesJob to Images::Processor service (H4)
- Slimmed FaviconFetchJob via Favicons::Fetcher, SourceHealthCheckJob via Health::SourceHealthCheckOrchestrator, ImportSessionHealthCheckJob via ImportSessions::HealthCheckUpdater (M12-M14)
- Fixed swallowed exception in Scraping::State broadcast_item with Rails.logger.warn (M17)
- Documented StalledFetchReconciler PG JSON operator query with SolidQueue version info (M18)

## Commits

- `0286b56` refactor(07-03): extract ScrapeItemJob to Scraping::Runner + remove duplicate rate-limiting (H3+H5)
- `176b336` refactor(07-03): extract DownloadContentImagesJob to Images::Processor (H4)
- `a44a302` refactor(07-03): slim FaviconFetchJob, SourceHealthCheckJob, ImportSessionHealthCheckJob (M12-M14)
- `61a515c` fix(07-03): fix swallowed exceptions in Scraping::State + document StalledFetchReconciler PG query (M17+M18)
- `6a8bf01` style(07-03): fix RuboCop array bracket spacing in HealthCheckUpdater

## Tasks Completed

- Extract ImportOpmlJob to OPMLImporter service (H2) -- already done by prior agent
- Extract ScrapeItemJob logic + remove duplicate rate-limiting (H3+H5)
- Extract DownloadContentImagesJob to Images::Processor (H4)
- Slim remaining fat jobs: FaviconFetchJob, SourceHealthCheckJob, ImportSessionHealthCheckJob (M12-M14)
- Fix swallowed exceptions and fragile PG query (M17+M18)

## Files Modified

- `app/jobs/source_monitor/scrape_item_job.rb` (73 -> 21 lines)
- `app/jobs/source_monitor/download_content_images_job.rb` (95 -> 16 lines)
- `app/jobs/source_monitor/favicon_fetch_job.rb` (94 -> 16 lines)
- `app/jobs/source_monitor/source_health_check_job.rb` (85 -> 16 lines)
- `app/jobs/source_monitor/import_session_health_check_job.rb` (99 -> 32 lines)
- `lib/source_monitor/scraping/runner.rb` (created)
- `lib/source_monitor/images/processor.rb` (created)
- `lib/source_monitor/favicons/fetcher.rb` (created)
- `lib/source_monitor/health/source_health_check_orchestrator.rb` (created)
- `lib/source_monitor/import_sessions/health_check_updater.rb` (created)
- `lib/source_monitor/scraping/state.rb` (broadcast exception logging)
- `lib/source_monitor/fetching/stalled_fetch_reconciler.rb` (PG query documentation)
- `lib/source_monitor/health.rb` (require orchestrator)
- `lib/source_monitor.rb` (autoloads for Runner, Processor, Fetcher, HealthCheckUpdater)
- `test/jobs/source_monitor/scrape_item_job_test.rb` (delegation-focused)
- `test/jobs/source_monitor/download_content_images_job_test.rb` (delegation-focused)
- `test/lib/source_monitor/scraping/runner_test.rb` (created)
- `test/lib/source_monitor/images/processor_test.rb` (created)

## Pre-existing Issues

- `EventSystemTest` (2 errors): NoMethodError on `process_feed_entries` -- caused by unstaged feed_fetcher.rb changes from Plan 05
- `FilterDropdownComponentTest` (1 failure): onchange assertion mismatch -- caused by Plan 04 Stimulus conversion

## Deviations

None.
