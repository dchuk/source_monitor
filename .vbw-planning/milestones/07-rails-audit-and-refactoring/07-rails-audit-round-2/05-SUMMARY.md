---
phase: 7
plan: 05
title: Test Reliability & Codebase Cleanup
status: complete
started_at: "2026-03-14"
completed_at: "2026-03-14"
tasks_completed: 5
tasks_total: 5
commits:
  - 83b54c7
  - e4e7e14
  - 21dadcb
  - c6a1822
  - 2148ec3
  - c81625d
  - 6c597a0
test_results: "1686 runs, 4987 assertions, 0 failures, 0 errors"
rubocop_results: "0 offenses on modified files"
deviations: []
---

## What Was Built

- Fixed pagination test parallel-safety (H6): replaced 7 `Source.destroy_all` calls with `clean_source_monitor_tables!` in sources_controller_test.rb
- Added FetchLogsController and ScrapeLogsController test files (L30): 10 new tests covering show action, error rendering, 404 handling
- Consolidated `configure_authentication` helper (L28): extracted to `test/support/authentication_helpers.rb`, removed 5 duplicate definitions
- Removed 30 forwarding methods (L14): 12 from FeedFetcher, 18 from ItemCreator; updated all tests to call sub-modules directly
- Removed 6 duplicated constants from FeedFetcher (L15): now referenced via `AdaptiveInterval::CONSTANT`
- Added exception logging for swallowed rescues (M17 partial): AIA recovery and CloudflareBypass now log warnings
- Standardized Images::Downloader HTTP client (L17): replaced raw `Faraday.new` with `SourceMonitor::HTTP.client`
- Added CloudflareBypass attempt limit (L19): `max_attempts` parameter (default: 2) and per-request `BYPASS_TIMEOUT` (10s)

## Files Modified

- `test/controllers/source_monitor/sources_controller_test.rb` -- replace destroy_all with clean_source_monitor_tables!
- `test/controllers/source_monitor/fetch_logs_controller_test.rb` -- new file, 5 tests
- `test/controllers/source_monitor/scrape_logs_controller_test.rb` -- new file, 5 tests
- `test/support/authentication_helpers.rb` -- new file, shared configure_authentication
- `test/test_helper.rb` -- require and include AuthenticationHelpers
- `test/controllers/source_monitor/import_sessions_controller_test.rb` -- use shared helper
- `test/controllers/source_monitor/import_history_dismissals_controller_test.rb` -- use shared helper
- `test/jobs/source_monitor/import_opml_job_test.rb` -- use shared helper
- `test/jobs/source_monitor/import_opml_favicon_test.rb` -- use shared helper
- `test/lib/source_monitor/import_sessions/opml_importer_test.rb` -- use shared helper
- `lib/source_monitor/fetching/feed_fetcher.rb` -- remove forwarding methods, duplicated constants, add AIA warning
- `lib/source_monitor/items/item_creator.rb` -- remove forwarding methods
- `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` -- no change (constants remain here)
- `lib/source_monitor/images/downloader.rb` -- use HTTP.client
- `lib/source_monitor/fetching/cloudflare_bypass.rb` -- add max_attempts, timeout, warning log
- `test/lib/source_monitor/fetching/feed_fetcher_utilities_test.rb` -- call sub-modules directly
- `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` -- use AdaptiveInterval constants
- `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb` -- add build_source_updater helper
- `test/lib/source_monitor/items/item_creator_test.rb` -- call sub-modules directly
- `test/lib/source_monitor/fetching/cloudflare_bypass_test.rb` -- adapt to max_attempts default
- `test/lib/source_monitor/events/event_system_test.rb` -- use EntryProcessor directly
