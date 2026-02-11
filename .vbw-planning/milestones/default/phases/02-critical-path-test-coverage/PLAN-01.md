---
phase: 2
plan: 1
title: feed-fetcher-tests
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with zero failures"
    - "Coverage report shows lib/source_monitor/fetching/feed_fetcher.rb has fewer than 50 uncovered lines (down from 245)"
    - "All new tests use WebMock stubs or VCR cassettes -- no real HTTP requests"
    - "Running `bin/rails test` exits 0 with no regressions"
  artifacts:
    - "test/lib/source_monitor/fetching/feed_fetcher_test.rb -- extended with new test methods covering retry strategy, error handling, header management, entry processing, and helper methods"
  key_links:
    - "REQ-01 substantially satisfied -- FeedFetcher branch coverage above 80%"
---

# Plan 01: feed-fetcher-tests

## Objective

Close the coverage gap in `lib/source_monitor/fetching/feed_fetcher.rb` (currently 245 uncovered lines out of 627). The existing test file covers basic RSS/Atom/JSON fetching, 304 handling, timeout/HTTP/parsing failures, and adaptive interval mechanics. This plan targets the remaining uncovered branches: retry strategy application, circuit breaker state transitions, connection error wrapping, last_modified header handling, entry processing edge cases, jitter computation, and private helper methods.

## Context

<context>
@lib/source_monitor/fetching/feed_fetcher.rb -- 627 lines, the core fetch pipeline
@lib/source_monitor/fetching/retry_policy.rb -- RetryPolicy with Decision struct
@lib/source_monitor/fetching/fetch_error.rb -- error hierarchy (TimeoutError, ConnectionError, HTTPError, ParsingError, UnexpectedResponseError)
@test/lib/source_monitor/fetching/feed_fetcher_test.rb -- existing test file with 12 tests covering success, 304, timeout, HTTP 404, parsing failure, adaptive intervals
@config/coverage_baseline.json -- lists 245 uncovered lines for feed_fetcher.rb
@test/test_helper.rb -- test infrastructure (WebMock, VCR, create_source!, with_queue_adapter)

**Decomposition rationale:** FeedFetcher is the single largest coverage gap (245 lines). It is tested in isolation from ItemCreator (which has its own plan). The uncovered code falls into distinct categories that can each be addressed as a focused task: (1) retry/circuit breaker logic, (2) Faraday error wrapping and connection failures, (3) header and metadata management, (4) entry processing edge cases, (5) jitter and interval helpers. Each task adds test methods to the existing test file.

**Trade-offs considered:**
- Could split FeedFetcher tests across multiple test files (e.g., feed_fetcher_retry_test.rb), but keeping them in one file matches the existing codebase convention and avoids confusion.
- Could use mocks for RetryPolicy, but testing the integration between FeedFetcher and RetryPolicy provides higher confidence.

**What constrains the structure:**
- Tests must use WebMock stubs (no real HTTP)
- All tests go in the existing test file to avoid file proliferation
- The `jitter: ->(_) { 0 }` pattern from existing tests should be reused to make interval assertions deterministic
- Tests need `travel_to` for time-sensitive assertions
</context>

## Tasks

### Task 1: Test retry strategy and circuit breaker transitions

- **name:** test-retry-and-circuit-breaker
- **files:**
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- **action:** Add tests covering lines 262-298 (reset_retry_state!, apply_retry_strategy!) and lines 267-290 (retry/circuit decisions). Specifically:
  1. Test that a first timeout failure sets fetch_retry_attempt to 1 (retry decision with wait)
  2. Test that exhausting retry attempts opens the circuit (sets fetch_circuit_opened_at, fetch_circuit_until, next_fetch_at)
  3. Test that a successful fetch after retries resets retry state (fetch_retry_attempt=0, circuit fields nil)
  4. Test that apply_retry_strategy! handles StandardError by logging and setting defaults (lines 291-298) -- simulate by stubbing RetryPolicy to raise
  5. Test that retry decision adjusts next_fetch_at to the minimum of current and retry time (line 283)
  Use WebMock stubs: first stub raises Faraday::TimeoutError to trigger retries, then stub success for recovery tests. Set source.fetch_retry_attempt manually to simulate multiple failures.
- **verify:** `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n /retry|circuit/` exits 0
- **done:** Lines 262-298 covered. Source retry fields verified in assertions.

### Task 2: Test Faraday error wrapping and connection failures

- **name:** test-faraday-error-wrapping
- **files:**
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- **action:** Add tests covering lines 77-86 (perform_fetch error wrapping) and lines 405-417 (build_http_error_from_faraday). Specifically:
  1. Test that Faraday::ConnectionFailed raises SourceMonitor::Fetching::ConnectionError with original_error preserved
  2. Test that Faraday::SSLError raises ConnectionError
  3. Test that Faraday::ClientError with response hash builds HTTPError via build_http_error_from_faraday (lines 405-417) with correct status, message, and ResponseWrapper
  4. Test that generic Faraday::Error raises FetchError
  5. Test that a non-Faraday StandardError is wrapped in UnexpectedResponseError (lines 52-54)
  Use WebMock's `to_raise` for each error type. Assert the result.error class, message, and original_error.
- **verify:** `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n /connection|ssl|client_error|unexpected|faraday/i` exits 0
- **done:** Lines 77-86 and 405-417 covered. All Faraday error types correctly wrapped.

### Task 3: Test Last-Modified header handling and request headers

- **name:** test-last-modified-and-headers
- **files:**
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- **action:** Add tests covering lines 97-104 (request_headers with custom_headers, etag, last_modified), lines 203-215 and 228-240 (response Last-Modified parsing and storage), and lines 349-355 (parse_http_time). Specifically:
  1. Test that If-Modified-Since header is sent when source.last_modified is set
  2. Test that Last-Modified response header is parsed and stored on source
  3. Test that malformed Last-Modified headers are silently ignored (parse_http_time returns nil for invalid dates, line 353)
  4. Test that custom_headers from source are passed through to the request (lines 98)
  5. Test that both ETag and Last-Modified are preserved on 304 not_modified responses (lines 228-234)
  Use WebMock to verify request headers via `.with(headers: {...})` and return specific response headers.
- **verify:** `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n /last_modified|custom_header|if_modified/i` exits 0
- **done:** Lines 97-104, 203-215, 228-240, 349-355 covered.

### Task 4: Test entry processing edge cases and error normalization

- **name:** test-entry-processing-edges
- **files:**
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- **action:** Add tests covering lines 520-567 (process_feed_entries) and lines 603-624 (normalize_item_error, safe_entry_guid, safe_entry_title). Specifically:
  1. Test that a feed without entries (feed that doesn't respond_to :entries) returns zero counts (line 529)
  2. Test that Events.run_item_processors is called for each entry (line 542)
  3. Test that Events.after_item_created is called only for created items (line 547), not updated ones
  4. Test that normalize_item_error extracts guid via entry_id (line 615-616), falls back to id (line 617-618), and handles entries without either
  5. Test that safe_entry_title returns nil when entry doesn't respond_to :title (line 623)
  Use a simple XML feed fixture with known entries. Mock ItemCreator to control created vs updated results. Use Notifications subscriptions to verify event dispatch.
- **verify:** `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n /entry_processing|item_processor|normalize_error|safe_entry/i` exits 0
- **done:** Lines 520-567, 603-624 covered.

### Task 5: Test jitter, interval helpers, and metadata management

- **name:** test-jitter-and-interval-helpers
- **files:**
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- **action:** Add tests covering lines 490-518 (jitter_offset, adjusted_interval_with_jitter, body_digest, updated_metadata) and lines 569-600 (configured_seconds, configured_positive, configured_non_negative, extract_numeric, fetching_config). Specifically:
  1. Test jitter_offset returns 0 when interval_seconds <= 0 (line 505)
  2. Test jitter_offset uses jitter_proc when provided (line 506)
  3. Test jitter_offset computes random jitter within expected range when no proc given
  4. Test body_digest returns nil for blank body (line 515), returns SHA256 for non-blank
  5. Test updated_metadata preserves existing metadata, removes dynamic_fetch_interval_seconds key, adds last_feed_signature
  6. Test configured_seconds returns default when minutes_value is nil or non-positive (lines 570-571)
  7. Test extract_numeric handles Numeric, responds_to :to_f, and non-numeric values (lines 590-596)
  These are private methods -- test them through the public `call` method by configuring specific fetching settings and verifying the resulting source state. Alternatively, use `send` for the pure-function helpers.
- **verify:** `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n /jitter|body_digest|metadata|configured_|extract_numeric/i` exits 0
- **done:** Lines 490-518 and 569-600 covered.

## Verification

1. `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0
2. `COVERAGE=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` shows feed_fetcher.rb with >80% branch coverage
3. `bin/rails test` exits 0 (no regressions)

## Success Criteria

- [ ] FeedFetcher coverage drops from 245 uncovered lines to fewer than 50
- [ ] All retry/circuit breaker branches tested
- [ ] All Faraday error wrapping branches tested
- [ ] All header handling branches tested
- [ ] Entry processing and error normalization branches tested
- [ ] Jitter, interval helpers, and metadata management tested
- [ ] REQ-01 substantially satisfied
