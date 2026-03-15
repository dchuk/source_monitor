---
phase: "06"
plan: "01"
title: Centralize Factory Helpers
status: complete
---

## What Was Built

Created a shared ModelFactories module in test/support/model_factories.rb consolidating 7 factory helpers (create_source!, create_item!, create_fetch_log!, create_scrape_log!, create_health_check_log!, create_log_entry!, create_item_content!) that were previously duplicated across 16+ test files. Moved create_source! from test_helper.rb into the module. Wired the module into ActiveSupport::TestCase. Migrated all test files with local factory definitions to use shared versions, removing ~100 lines of duplicated helper code. Full test suite (1622 tests) passes with zero failures.

## Commits

- `18692f6` refactor(06-01): centralize factory helpers into ModelFactories module

## Tasks Completed

- Create ModelFactories module
- Wire factories into test_helper
- Migrate test files to shared factories
- Verify and document

## Files Modified

- `test/support/model_factories.rb` -- new shared factory module with 7 helpers
- `test/test_helper.rb` -- require + include ModelFactories, removed inline create_source!
- `test/lib/source_monitor/items/retention_pruner_test.rb` -- removed build_source, create_item
- `test/lib/source_monitor/scraping/enqueuer_test.rb` -- removed create_source, create_item, create_scrape_log
- `test/lib/source_monitor/scraping/state_test.rb` -- removed create_source, create_item
- `test/lib/source_monitor/scraping/scheduler_test.rb` -- removed create_source, create_item
- `test/lib/source_monitor/scraping/bulk_source_scraper_test.rb` -- removed create_item!
- `test/lib/source_monitor/realtime/broadcaster_test.rb` -- removed create_item!
- `test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` -- removed create_item!
- `test/lib/source_monitor/health/source_health_monitor_test.rb` -- updated create_fetch_log to delegate to shared factory
- `test/lib/source_monitor/items/item_creator_test.rb` -- removed build_source
- `test/lib/source_monitor/events/event_system_test.rb` -- removed build_source
- `test/lib/source_monitor/scraping/item_scraper/adapter_resolver_test.rb` -- removed build_source
- `test/jobs/source_monitor/download_content_images_job_test.rb` -- removed create_item!
- `test/jobs/source_monitor/scrape_item_job_test.rb` -- removed create_source, create_item, create_scrape_log
- `test/jobs/source_monitor/log_cleanup_job_test.rb` -- removed create_source, create_item, create_fetch_log, create_scrape_log
- `test/jobs/source_monitor/item_cleanup_job_test.rb` -- removed create_source, create_item

## Deviations

- `source_health_monitor_test.rb` retains a thin `create_fetch_log` wrapper (no bang) that adds `minutes_ago` convenience param and delegates to shared `create_fetch_log!`. This is genuinely unique test-specific logic (DEVN-01).
- `feed_fetcher_test_helper.rb` retains its `build_source` -- it is an existing shared module (not a local duplicate) used by 7+ fetching test files with a distinct required-keyword signature. Out of scope per plan intent.
- `source_scrape_tests_controller_test.rb` retains `create_item_with_content!` -- different method name with specialized item+content creation logic.
