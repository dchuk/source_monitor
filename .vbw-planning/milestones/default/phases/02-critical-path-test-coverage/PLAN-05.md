---
phase: 2
plan: 5
title: scraping-and-broadcasting-tests
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `bin/rails test test/lib/source_monitor/scraping/bulk_source_scraper_test.rb test/lib/source_monitor/realtime/broadcaster_test.rb` exits 0 with zero failures"
    - "Coverage report shows lib/source_monitor/scraping/bulk_source_scraper.rb has fewer than 15 uncovered lines (down from 66)"
    - "Coverage report shows lib/source_monitor/realtime/broadcaster.rb has fewer than 10 uncovered lines (down from 48)"
    - "Running `bin/rails test` exits 0 with no regressions"
  artifacts:
    - "test/lib/source_monitor/scraping/bulk_source_scraper_test.rb -- extended with tests for disabled result, invalid selection, batch limiting, determine_status, and selection_counts edge cases"
    - "test/lib/source_monitor/realtime/broadcaster_test.rb -- new test file covering setup!, broadcast_source, broadcast_item, broadcast_toast, event handlers, and error logging"
  key_links:
    - "REQ-05 substantially satisfied -- Broadcaster branch coverage above 80%"
    - "REQ-06 substantially satisfied -- BulkSourceScraper branch coverage above 80%"
---

# Plan 05: scraping-and-broadcasting-tests

## Objective

Close the coverage gaps in `lib/source_monitor/scraping/bulk_source_scraper.rb` (66 uncovered lines) and `lib/source_monitor/realtime/broadcaster.rb` (48 uncovered lines). For BulkSourceScraper, the existing tests cover current/unscraped/all selections, rate limiting, and selection_counts. This plan targets the remaining uncovered branches: disabled_result, invalid_selection_result, batch limiting, determine_status edge cases, and selection normalization. For Broadcaster, there is no existing test file -- this plan creates one covering setup!, broadcast_source, broadcast_item, broadcast_toast, fetch/item event handlers, error swallowing, and turbo_available? checks.

## Context

<context>
@lib/source_monitor/scraping/bulk_source_scraper.rb -- 234 lines, bulk scrape orchestration
@lib/source_monitor/realtime/broadcaster.rb -- 238 lines, Action Cable broadcasting module
@test/lib/source_monitor/scraping/bulk_source_scraper_test.rb -- existing test file with 6 tests
@lib/source_monitor/scraping/enqueuer.rb -- Enqueuer used by BulkSourceScraper
@lib/source_monitor/scraping/state.rb -- State module for in-flight status tracking
@config/coverage_baseline.json -- lists uncovered lines for both files

**Decomposition rationale:** BulkSourceScraper and Broadcaster are the remaining REQ-05/REQ-06 targets. BulkSourceScraper has a partially-tested test file that needs extension. Broadcaster has no test file and needs creation. They don't share files, so combining them in one plan is safe. The combined gap (114 lines) fits within 5 tasks.

**Trade-offs considered:**
- Broadcaster depends on Turbo::StreamsChannel for broadcasting. Tests should mock/stub Turbo calls rather than require a full Action Cable setup.
- BulkSourceScraper's batch limiting tests need to configure max_bulk_batch_size.
- Broadcaster's setup! method registers callbacks on the events system -- tests should verify callbacks are registered and handle events correctly.
- Error swallowing paths (rescue StandardError => error with log_error) need to verify the error is logged but doesn't propagate.

**What constrains the structure:**
- Broadcaster tests must handle turbo_available? returning true or false
- Tests must not leak registered callbacks between tests (use reset_configuration!)
- BulkSourceScraper tests extend the existing file
- Broadcaster tests go in a new file at the expected path
</context>

## Tasks

### Task 1: Test BulkSourceScraper disabled and invalid selection paths

- **name:** test-bulk-scraper-disabled-and-invalid
- **files:**
  - `test/lib/source_monitor/scraping/bulk_source_scraper_test.rb`
- **action:** Add tests covering lines 76-77 (disabled_result, invalid_selection_result) and lines 190-230 (disabled_result, invalid_selection_result, no_items_result). Specifically:
  1. Test that calling bulk scraper on a source with scraping_enabled: false returns error result with failure_details: { scraping_disabled: 1 } (lines 190-202)
  2. Test that an unrecognized selection value (after normalization returns nil, which defaults to :current) still works, and that calling with a selection that is neither in SELECTIONS after constructor normalization handles correctly
  3. Test the Result struct methods: success?, partial?, error?, rate_limited? (lines 29-43)
  4. Test normalize_selection with various inputs: symbol, string with whitespace, uppercase, nil, invalid string returns nil (lines 60-64)
  5. Test selection_label with valid and invalid selection values (lines 46-48)
- **verify:** `bin/rails test test/lib/source_monitor/scraping/bulk_source_scraper_test.rb -n /disabled|invalid_selection|result_struct|normalize|selection_label/i` exits 0
- **done:** Lines 29-48, 60-64, 76-77, 190-230 covered.

### Task 2: Test BulkSourceScraper batch limiting and determine_status

- **name:** test-bulk-scraper-batch-limit-and-status
- **files:**
  - `test/lib/source_monitor/scraping/bulk_source_scraper_test.rb`
- **action:** Add tests covering lines 169-188 (apply_batch_limit, determine_status) and lines 130-153 (scoped_items, without_inflight). Specifically:
  1. Test apply_batch_limit respects max_bulk_batch_size from config -- create 10 items, set max_bulk_batch_size to 3, verify only 3 enqueued for :all selection (lines 169-176)
  2. Test apply_batch_limit uses min of current limit_value and config limit (line 174) -- :current with preview_limit=5 and max_bulk_batch_size=3 uses 3
  3. Test determine_status returns :success when enqueued > 0 and failure = 0 (line 179-180)
  4. Test determine_status returns :partial when enqueued > 0 and failure > 0 (line 181-182)
  5. Test determine_status returns :partial when only already_enqueued > 0 (line 183-184)
  6. Test determine_status returns :error when enqueued = 0 and already_enqueued = 0 (line 185-186)
  7. Test without_inflight excludes items with in-flight scrape_status (pending/processing) from the scope (lines 150-153)
  Configure SourceMonitor.config.scraping.max_bulk_batch_size for batch limit tests.
- **verify:** `bin/rails test test/lib/source_monitor/scraping/bulk_source_scraper_test.rb -n /batch_limit|determine_status|without_inflight/i` exits 0
- **done:** Lines 130-188 covered.

### Task 3: Test Broadcaster setup and broadcast_source/broadcast_item

- **name:** test-broadcaster-setup-and-broadcasts
- **files:**
  - `test/lib/source_monitor/realtime/broadcaster_test.rb` (new file)
- **action:** Create a new test file and add tests covering lines 14-64 (setup!, broadcast_source, broadcast_item). Specifically:
  1. Test setup! registers after_fetch_completed and after_item_scraped callbacks with the events system (lines 18-19) -- verify callbacks_for returns the callbacks
  2. Test setup! is idempotent (calling twice doesn't double-register) (lines 16, 21)
  3. Test broadcast_source returns early when turbo_available? is false (line 33)
  4. Test broadcast_source returns early when source is nil after reload (line 35)
  5. Test broadcast_source calls broadcast_source_row and broadcast_source_show -- stub Turbo::StreamsChannel.broadcast_replace_to and verify it receives expected arguments
  6. Test broadcast_item calls Turbo::StreamsChannel.broadcast_replace_to with correct target and partial (lines 46-54)
  7. Test broadcast_item rescues errors and logs them (line 62-63)
  Use stubs for Turbo::StreamsChannel methods and controller render calls. Set @setup = nil before tests to allow re-testing setup!. Reset configuration in teardown.
- **verify:** `bin/rails test test/lib/source_monitor/realtime/broadcaster_test.rb -n /setup|broadcast_source|broadcast_item/i` exits 0
- **done:** Lines 14-64 covered.

### Task 4: Test Broadcaster toast broadcasting and event handlers

- **name:** test-broadcaster-toast-and-events
- **files:**
  - `test/lib/source_monitor/realtime/broadcaster_test.rb`
- **action:** Add tests covering lines 66-152 (broadcast_toast, handle_fetch_completed, handle_item_scraped, broadcast_fetch_toast, broadcast_item_toast). Specifically:
  1. Test broadcast_toast returns early when turbo_available? is false (line 67)
  2. Test broadcast_toast returns early when message is blank (line 68)
  3. Test broadcast_toast calls Turbo::StreamsChannel.broadcast_append_to with NOTIFICATION_STREAM, target, and rendered HTML (lines 70-82)
  4. Test broadcast_toast rescues errors and doesn't propagate (line 83-84)
  5. Test handle_fetch_completed broadcasts source and toast -- verify toast message for "fetched" status includes source name and counts (lines 112-119)
  6. Test broadcast_fetch_toast for "not_modified" status broadcasts info-level toast (lines 120-124)
  7. Test broadcast_fetch_toast for "failed" status broadcasts error-level toast with error message (lines 125-134)
  8. Test handle_item_scraped broadcasts item, source, and toast (lines 97-104)
  9. Test broadcast_item_toast for failed status includes error level (lines 143-146)
  10. Test broadcast_item_toast for success status includes success level (lines 147-151)
  Use mock events with Struct to simulate fetch_completed and item_scraped events. Stub Turbo and controller render calls.
- **verify:** `bin/rails test test/lib/source_monitor/realtime/broadcaster_test.rb -n /toast|fetch_completed|item_scraped|fetch_toast|item_toast/i` exits 0
- **done:** Lines 66-152 covered.

### Task 5: Test Broadcaster helpers: reload_record, turbo_available?, register_callback, log methods

- **name:** test-broadcaster-helpers
- **files:**
  - `test/lib/source_monitor/realtime/broadcaster_test.rb`
- **action:** Add tests covering lines 154-234 (broadcast_source_row, broadcast_source_show, reload_record, turbo_available?, register_callback, log_info, log_error, item_stream_identifier, source_stream_identifier). Specifically:
  1. Test reload_record returns nil for nil input (line 191)
  2. Test reload_record returns the original record when reload raises (line 194-195)
  3. Test turbo_available? returns true when Turbo::StreamsChannel is defined, false otherwise (line 218)
  4. Test register_callback doesn't double-register the same callback (lines 222-224)
  5. Test log_error swallows errors from the logger itself (line 232-233)
  6. Test log_info returns nil when Rails.logger is nil (line 199)
  7. Test broadcast_source_row and broadcast_source_show rescue errors and call log_error (lines 166-167, 186-187)
  Use stubs and mocks for Rails.logger and Turbo.
- **verify:** `bin/rails test test/lib/source_monitor/realtime/broadcaster_test.rb -n /reload_record|turbo_available|register_callback|log_error|log_info/i` exits 0
- **done:** Lines 154-234 covered.

## Verification

1. `bin/rails test test/lib/source_monitor/scraping/bulk_source_scraper_test.rb` exits 0
2. `bin/rails test test/lib/source_monitor/realtime/broadcaster_test.rb` exits 0
3. `COVERAGE=1 bin/rails test test/lib/source_monitor/scraping/bulk_source_scraper_test.rb test/lib/source_monitor/realtime/broadcaster_test.rb` shows both files with >80% branch coverage
4. `bin/rails test` exits 0 (no regressions)

## Success Criteria

- [ ] BulkSourceScraper coverage drops from 66 uncovered lines to fewer than 15
- [ ] Broadcaster coverage drops from 48 uncovered lines to fewer than 10
- [ ] BulkSourceScraper disabled/invalid/batch/status paths tested
- [ ] Broadcaster setup, broadcasting, toast, and event handlers tested
- [ ] Broadcaster error swallowing and helper methods tested
- [ ] REQ-05 and REQ-06 substantially satisfied
