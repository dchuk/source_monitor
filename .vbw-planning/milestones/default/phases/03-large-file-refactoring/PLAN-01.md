---
phase: 3
plan: 1
title: extract-feed-fetcher
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `wc -l lib/source_monitor/fetching/feed_fetcher.rb` shows fewer than 300 lines"
    - "Running `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with zero failures"
    - "Running `bin/rails test` exits 0 with no regressions (760+ runs, 0 failures)"
    - "Running `grep -r 'FeedFetcher' test/ --include='*.rb' -l` shows no test files were renamed or removed"
    - "Running `ruby -c lib/source_monitor/fetching/feed_fetcher.rb` exits 0 (valid syntax)"
    - "Running `ruby -c lib/source_monitor/fetching/feed_fetcher/source_updater.rb` exits 0"
    - "Running `ruby -c lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` exits 0"
    - "Running `ruby -c lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` exits 0"
  artifacts:
    - "lib/source_monitor/fetching/feed_fetcher/source_updater.rb -- extracted source state update logic"
    - "lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb -- extracted adaptive interval computation"
    - "lib/source_monitor/fetching/feed_fetcher/entry_processor.rb -- extracted feed entry processing"
    - "lib/source_monitor/fetching/feed_fetcher.rb -- slimmed to orchestrator under 300 lines"
  key_links:
    - "REQ-08 satisfied -- FeedFetcher broken into focused single-responsibility modules"
    - "Public API unchanged -- FeedFetcher.new(source:).call still returns Result struct"
---

# Plan 01: extract-feed-fetcher

## Objective

Extract `lib/source_monitor/fetching/feed_fetcher.rb` (627 lines) into focused sub-modules following the existing extraction pattern used by `item_scraper/` (which already has `adapter_resolver.rb` and `persistence.rb` sub-modules) and `completion/` (which has `event_publisher.rb`, `follow_up_handler.rb`, `retention_handler.rb`). The public API (`FeedFetcher.new(source:).call` returning a `Result` struct) must remain unchanged. All 1219 lines of existing tests in `feed_fetcher_test.rb` must continue to pass without modification.

## Context

<context>
@lib/source_monitor/fetching/feed_fetcher.rb -- 627 lines, the core fetch pipeline. Contains HTTP request handling, feed parsing, entry processing, source state updates (success/not_modified/failure), adaptive interval computation, retry strategy application, fetch logging, error wrapping, and various utility helpers.
@lib/source_monitor/fetching/retry_policy.rb -- 85 lines, already extracted. RetryPolicy with Decision struct.
@lib/source_monitor/fetching/fetch_error.rb -- 88 lines, already extracted. Error hierarchy.
@lib/source_monitor/fetching/completion/ -- existing extraction pattern: event_publisher.rb (22 lines), follow_up_handler.rb (37 lines), retention_handler.rb (30 lines). These are loaded via require from fetch_runner.rb.
@lib/source_monitor/scraping/item_scraper.rb -- another extraction example: main class requires item_scraper/adapter_resolver.rb and item_scraper/persistence.rb
@test/lib/source_monitor/fetching/feed_fetcher_test.rb -- 1219 lines, 48+ tests covering all branches. MUST NOT be modified.
@lib/source_monitor.rb -- has `require "source_monitor/fetching/feed_fetcher"` on line 79. New sub-files will be required from feed_fetcher.rb itself (matching item_scraper pattern).

**Decomposition rationale:** FeedFetcher has three clearly separable responsibility clusters: (1) source state updates after fetch (update_source_for_success, update_source_for_not_modified, update_source_for_failure, reset_retry_state!, apply_retry_strategy!, create_fetch_log -- ~120 lines), (2) adaptive interval computation (apply_adaptive_interval!, compute_next_interval_seconds, adjusted_interval_with_jitter, jitter_offset, and all interval config helpers -- ~110 lines), (3) entry processing (process_feed_entries, normalize_item_error, safe_entry_guid, safe_entry_title -- ~80 lines). The remaining orchestration (call, perform_fetch, handle_response, handle_success, handle_not_modified, handle_failure, HTTP helpers) stays in the main file.

**Trade-offs considered:**
- Could extract HTTP/connection as a fourth module, but perform_request and connection are only ~10 lines and tightly coupled to the orchestrator.
- Could use Ruby mixins (include/extend) instead of delegation, but delegation preserves clear ownership and matches the item_scraper pattern.
- Structs (Result, EntryProcessingResult, ResponseWrapper) stay in the main file because they define the public API contract.

**What constrains the structure:**
- The main file must require its sub-modules (matching item_scraper pattern)
- Sub-modules need access to source, fetching_config, and other state -- pass via constructor or delegate
- All tests pass without modification -- the public API is preserved
- Each extracted module lives in lib/source_monitor/fetching/feed_fetcher/ directory (matching item_scraper/ pattern)
</context>

## Tasks

**Execution note:** Task 2 (AdaptiveInterval) should be completed before Task 1 (SourceUpdater) because SourceUpdater depends on AdaptiveInterval for the `apply_adaptive_interval!` method. Task 3 (EntryProcessor) is independent of the other two. Task 4 is the final wiring pass.

### Task 1: Extract SourceUpdater module

- **name:** extract-source-updater
- **files:**
  - `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` (new)
  - `lib/source_monitor/fetching/feed_fetcher.rb`
- **action:** Create `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` containing a `SourceMonitor::Fetching::FeedFetcher::SourceUpdater` class. Move these methods from feed_fetcher.rb into the new class:
  - `update_source_for_success` (lines 192-216)
  - `update_source_for_not_modified` (lines 218-241)
  - `update_source_for_failure` (lines 243-259)
  - `reset_retry_state!` (lines 261-265)
  - `apply_retry_strategy!` (lines 267-299)
  - `create_fetch_log` (lines 301-320)
  - `feed_metadata` (lines 328-335)
  - `normalized_headers` (lines 337-341)
  - `error_backtrace` (lines 343-347)
  - `derive_feed_format` (lines 322-326)
  - `feed_signature_changed?` (lines 419-423)
  - `updated_metadata` (lines 490-495)
  - `parse_http_time` (lines 349-355)
  - `elapsed_ms` (lines 357-359)

  The SourceUpdater constructor takes `source:` and `adaptive_interval:` (the AdaptiveInterval instance from Task 2). Add `require "source_monitor/fetching/feed_fetcher/source_updater"` at the top of feed_fetcher.rb. In FeedFetcher, create a `source_updater` method that lazily instantiates the SourceUpdater passing source and adaptive_interval. Replace all calls to the moved methods with delegation to `source_updater.method_name`. The SourceUpdater must be a private implementation detail -- not exposed in the public API.
- **verify:** `ruby -c lib/source_monitor/fetching/feed_fetcher/source_updater.rb` exits 0 AND `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with zero failures
- **done:** SourceUpdater extracted. All calls delegated. Tests pass unchanged.

### Task 2: Extract AdaptiveInterval module

- **name:** extract-adaptive-interval
- **files:**
  - `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` (new)
  - `lib/source_monitor/fetching/feed_fetcher.rb`
- **action:** Create `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` containing a `SourceMonitor::Fetching::FeedFetcher::AdaptiveInterval` class. Move these methods:
  - `apply_adaptive_interval!` (lines 425-438)
  - `compute_next_interval_seconds` (lines 441-455)
  - `current_interval_seconds` (lines 457-459)
  - `interval_minutes_for` (lines 461-464)
  - `min_fetch_interval_seconds` (lines 466-468)
  - `max_fetch_interval_seconds` (lines 470-472)
  - `increase_factor_value` (lines 474-476)
  - `decrease_factor_value` (lines 478-480)
  - `failure_increase_factor_value` (lines 482-484)
  - `jitter_percent_value` (lines 486-488)
  - `adjusted_interval_with_jitter` (lines 497-502)
  - `jitter_offset` (lines 504-512)
  - `configured_seconds` (lines 569-574)
  - `configured_positive` (lines 576-580)
  - `configured_non_negative` (lines 583-588)
  - `extract_numeric` (lines 590-597)
  - `fetching_config` (lines 599-601)

  Also move the constants: `MIN_FETCH_INTERVAL`, `MAX_FETCH_INTERVAL`, `INCREASE_FACTOR`, `DECREASE_FACTOR`, `FAILURE_INCREASE_FACTOR`, `JITTER_PERCENT`.

  The constructor takes `source:` and `jitter_proc:`. Add `require "source_monitor/fetching/feed_fetcher/adaptive_interval"` at the top of feed_fetcher.rb. In FeedFetcher, create an `adaptive_interval` method that lazily instantiates AdaptiveInterval. Replace all calls to moved methods with delegation. Keep the constant references working by aliasing from the main class or referencing the sub-module.
- **verify:** `ruby -c lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` exits 0 AND `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0
- **done:** AdaptiveInterval extracted. Constants accessible. Tests pass unchanged.

### Task 3: Extract EntryProcessor module

- **name:** extract-entry-processor
- **files:**
  - `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` (new)
  - `lib/source_monitor/fetching/feed_fetcher.rb`
- **action:** Create `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` containing a `SourceMonitor::Fetching::FeedFetcher::EntryProcessor` class. Move these methods:
  - `process_feed_entries` (lines 520-567)
  - `normalize_item_error` (lines 603-612)
  - `safe_entry_guid` (lines 614-620)
  - `safe_entry_title` (lines 622-624)

  The constructor takes `source:`. It returns `EntryProcessingResult` structs (which stay defined in the main FeedFetcher class and are referenced as `FeedFetcher::EntryProcessingResult`). Add `require "source_monitor/fetching/feed_fetcher/entry_processor"` at the top of feed_fetcher.rb. In FeedFetcher, create an `entry_processor` method and delegate `process_feed_entries` to it. The other methods are only called from within entry_processor so they move wholesale.
- **verify:** `ruby -c lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` exits 0 AND `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0
- **done:** EntryProcessor extracted. Tests pass unchanged.

### Task 4: Wire extracted modules and verify final line count

- **name:** wire-modules-and-verify
- **files:**
  - `lib/source_monitor/fetching/feed_fetcher.rb`
- **action:** After Tasks 1-3, the main feed_fetcher.rb should contain: require statements for the 3 sub-modules, the Struct definitions (Result, EntryProcessingResult, ResponseWrapper), the constructor, `call`, `perform_fetch`, `handle_response`, `handle_success`, `handle_not_modified`, `handle_failure`, `perform_request`, `connection`, `request_headers`, `build_http_error_from_faraday`, `body_digest`, and the lazy accessor methods for source_updater, adaptive_interval, and entry_processor. Clean up any dead code, unused private methods, or orphaned requires. Ensure no method is duplicated between the main file and sub-modules. Verify the main file is under 300 lines. Run the full test suite to confirm no regressions.
- **verify:** `wc -l lib/source_monitor/fetching/feed_fetcher.rb` shows fewer than 300 lines AND `bin/rails test` exits 0 with 760+ runs and 0 failures AND `bin/rubocop lib/source_monitor/fetching/feed_fetcher.rb lib/source_monitor/fetching/feed_fetcher/` exits 0
- **done:** FeedFetcher under 300 lines. All sub-modules syntactically valid. Full suite passes. RuboCop clean.

## Verification

1. `wc -l lib/source_monitor/fetching/feed_fetcher.rb` shows fewer than 300 lines
2. `wc -l lib/source_monitor/fetching/feed_fetcher/source_updater.rb lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` shows all exist
3. `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with zero failures
4. `bin/rails test` exits 0 (no regressions)
5. `bin/rubocop lib/source_monitor/fetching/` exits 0

## Success Criteria

- [ ] FeedFetcher main file under 300 lines
- [ ] Three sub-modules created: source_updater.rb, adaptive_interval.rb, entry_processor.rb
- [ ] Public API unchanged -- FeedFetcher.new(source:).call returns Result struct
- [ ] All existing tests pass without modification (1219 lines, 48+ tests)
- [ ] Full test suite passes (760+ runs, 0 failures)
- [ ] RuboCop passes on all modified/new files
- [ ] REQ-08 satisfied
