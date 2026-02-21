---
phase: 2
plan: 3
title: "Favicon Fetch Triggers: Source Creation and Feed Success"
status: complete
tasks_completed: 4
tasks_total: 4
commits:
  - 0fd4d49
  - dd93213
  - cc4962e
  - d99ca50
tests_added: 18
tests_pass: true
rubocop_offenses: 0
deviations: []
---

## What Was Built
- FaviconFetchJob trigger on manual source creation via SourcesController#create
- FaviconFetchJob trigger on successful feed fetch via SourceUpdater with cooldown check
- FaviconFetchJob trigger for each OPML-imported source with website_url
- End-to-end integration test: POST source -> enqueue -> perform -> verify attachment -> render show
- All triggers guard on ActiveStorage, favicons enabled, website_url present
- All triggers wrapped in rescue to never break the main flow

## Files Modified
- `app/controllers/source_monitor/sources_controller.rb` -- added enqueue_favicon_fetch private method, called from create action
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` -- added enqueue_favicon_fetch_if_needed with cooldown logic, called after update_source_for_success
- `app/jobs/source_monitor/import_opml_job.rb` -- added should_fetch_favicon? guard and enqueue call after each source.save
- `test/controllers/source_monitor/sources_controller_favicon_test.rb` -- 4 controller tests for create favicon trigger
- `test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb` -- 8 unit tests for updater favicon trigger with guards
- `test/jobs/source_monitor/import_opml_favicon_test.rb` -- 3 tests for OPML import favicon trigger
- `test/integration/source_monitor/favicon_integration_test.rb` -- 3 integration tests for end-to-end flow
