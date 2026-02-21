---
phase: "02"
plan: "01"
title: "Split FeedFetcherTest into Concern-Based Classes"
wave: 1
depends_on: []
must_haves:
  - "REQ-PERF-01: FeedFetcherTest split into 6+ independent test files by concern"
  - "Original feed_fetcher_test.rb deleted or replaced with require-only shim"
  - "Each new test file is independently runnable with PARALLEL_WORKERS=1"
  - "All 71 FeedFetcherTest tests pass individually and in full suite"
  - "Shared build_source and body_digest helpers extracted to shared module"
  - "RuboCop zero offenses on all new/modified test files"
skills_used: []
---

# Plan 01: Split FeedFetcherTest into Concern-Based Classes

## Objective

Split the monolithic `FeedFetcherTest` (71 tests, 84.8s, 64% of total runtime) into 6+ smaller test classes by concern. This is the single highest-impact optimization: Minitest parallelizes by class, so one 71-test class gets assigned to one worker. Splitting enables parallel distribution across all CPU cores.

## Context

- `@` `test/lib/source_monitor/fetching/feed_fetcher_test.rb` -- 1350-line monolithic test class (the file to split)
- `@` `test/test_helper.rb` -- base test setup with `create_source!` and `clean_source_monitor_tables!`
- `@` `test/test_prof.rb` -- TestProf `before_all` and `setup_once` support

**Rationale:** The test file already has section comments (Task 1-6) that map to concern groups. The `build_source` and `body_digest` private helpers are shared across all tests and must be extracted to a module.

## Tasks

### Task 1: Create shared helper module for FeedFetcher tests

Create `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb`:

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module FeedFetcherTestHelper
      private

      def build_source(name:, feed_url:, fetch_interval_minutes: 360, adaptive_fetching_enabled: true)
        create_source!(
          name: name,
          feed_url: feed_url,
          fetch_interval_minutes: fetch_interval_minutes,
          adaptive_fetching_enabled: adaptive_fetching_enabled
        )
      end

      def body_digest(body)
        Digest::SHA256.hexdigest(body)
      end
    end
  end
end
```

### Task 2: Create the 6 split test files

Split the 71 tests into these files, each requiring `test_helper` and `feed_fetcher_test_helper`:

1. **`feed_fetcher_success_test.rb`** (~13 tests) -- Success paths: RSS/Atom/JSON fetching, log entries, instrumentation notifications, ETag/304 handling, Netflix cassette test. Tests: "continues processing when an item creation fails", "fetches an RSS feed and records log entries", "reuses etag and handles 304", "parses rss atom and json feeds via feedjira", "fetches Netflix Tech Blog feed via Medium RSS".

2. **`feed_fetcher_error_handling_test.rb`** (~12 tests) -- Error wrapping and connection failures: all Faraday error type wrapping, AIA certificate resolution tests (retry on SSL, nil resolve, non-SSL skip), generic Faraday::Error, unexpected StandardError, HTTPError from ClientError, re-raise without double-wrap. Tests from "Task 2" section plus AIA tests.

3. **`feed_fetcher_adaptive_interval_test.rb`** (~8 tests) -- Adaptive fetch interval: decrease on content change, increase on no change, configured settings, min/max bounds, failure increase with backoff, disabled adaptive fetching. Tests from the interval section.

4. **`feed_fetcher_retry_circuit_test.rb`** (~7 tests) -- Retry strategy and circuit breaker: reset on success, reset on 304, apply retry state, circuit open when exhausted, next_fetch_at earliest logic, policy error handling. Tests from "Task 1" section.

5. **`feed_fetcher_entry_processing_test.rb`** (~7 tests) -- Entry processing: empty entries, error normalization (with guid, without guid), created/updated tracking, unchanged items, entries_digest fallback (url, title), failure result empty processing. Tests from "Task 4" section plus "process_feed_entries tracks created and updated" and "unchanged items".

6. **`feed_fetcher_utilities_test.rb`** (~16 tests) -- Utility methods: jitter_offset, adjusted_interval_with_jitter, body_digest, updated_metadata, feed_signature_changed?, configured_seconds, configured_positive, configured_non_negative, interval_minutes_for, parse_http_time, extract_numeric. Tests from "Task 5" section plus "Task 3" header tests (If-Modified-Since, custom_headers, ETag update, Last-Modified update/304/unparseable).

Each file follows this pattern:
```ruby
# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherSuccessTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper
      # tests here...
    end
  end
end
```

### Task 3: Delete original feed_fetcher_test.rb

After all 6 new files are created and verified, delete the original `test/lib/source_monitor/fetching/feed_fetcher_test.rb`. Do NOT keep a shim -- the new files are self-contained.

### Task 4: Verify all tests pass and lint clean

Run verification:
```bash
# Run each new file individually
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_success_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_error_handling_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_retry_circuit_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_entry_processing_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_utilities_test.rb

# Full suite
bin/rails test

# Lint
bin/rubocop test/lib/source_monitor/fetching/
```

Ensure the total test count remains 1031+ (no tests lost or duplicated).

## Files

| Action | Path |
|--------|------|
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_success_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_error_handling_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_retry_circuit_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_entry_processing_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher_utilities_test.rb` |
| DELETE | `test/lib/source_monitor/fetching/feed_fetcher_test.rb` |

## Verification

```bash
# Individual file runs (PARALLEL_WORKERS=1 due to PG fork segfault on single files)
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_success_test.rb
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_utilities_test.rb

# Full suite (all 1031+ tests pass)
bin/rails test

# Lint
bin/rubocop test/lib/source_monitor/fetching/
```

## Success Criteria

- 6+ new test files exist in `test/lib/source_monitor/fetching/`
- Original `feed_fetcher_test.rb` deleted
- `grep -c "class Feed" test/lib/source_monitor/fetching/*_test.rb` shows 6+ classes
- All 1031+ tests pass in full suite
- Each file runnable independently with PARALLEL_WORKERS=1
