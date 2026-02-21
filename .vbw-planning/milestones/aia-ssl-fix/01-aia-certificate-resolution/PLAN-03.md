---
phase: 1
plan: 3
title: "FeedFetcher AIA Retry Integration"
wave: 2
depends_on: [1, 2]
must_haves:
  - Separate Faraday::SSLError rescue from Faraday::ConnectionFailed
  - On SSLError attempt AIA resolution once (aia_attempted flag)
  - Parse hostname from source.feed_url for AIA resolve
  - If intermediate found rebuild connection with enhanced cert store and retry
  - If nil raise ConnectionError as before
  - Tag successful recoveries with aia_resolved in instrumentation
  - Integration tests for all AIA retry paths
  - Full test suite passes (1003+ tests)
  - RuboCop zero offenses
  - Brakeman zero warnings
---

# Plan 03: FeedFetcher AIA Retry Integration

## Goal

Wire AIA resolution into FeedFetcher's error handling so SSL failures automatically attempt intermediate certificate recovery before giving up.

## Tasks

### Task 1: Modify lib/source_monitor/fetching/feed_fetcher.rb

Modify `perform_fetch` (lines 77-90):

1. **Split rescue clause:** Separate `Faraday::SSLError` from `Faraday::ConnectionFailed` into its own rescue:
   ```ruby
   rescue Faraday::ConnectionFailed => error
     raise ConnectionError.new(error.message, original_error: error)
   rescue Faraday::SSLError => error
     attempt_aia_recovery(error) || raise(ConnectionError.new(error.message, original_error: error))
   ```

2. **Add `attempt_aia_recovery` private method:**
   - Guard: return nil if `@aia_attempted` is true (prevents recursion)
   - Set `@aia_attempted = true`
   - Parse hostname from `URI.parse(source.feed_url).host`
   - Call `SourceMonitor::HTTP::AIAResolver.resolve(hostname)`
   - If intermediate found:
     - Build enhanced cert store via `AIAResolver.enhanced_cert_store([intermediate])`
     - Rebuild `@connection = SourceMonitor::HTTP.client(cert_store: store, headers: request_headers)`
     - Return `perform_request` (the retry)
   - If nil: return nil (caller raises ConnectionError)
   - Rescue StandardError -> nil (never make retry worse)

3. **Tag instrumentation:** In the `handle_response` path after successful AIA retry, the `instrumentation_payload[:aia_resolved] = true` will naturally flow through since `perform_fetch` calls `handle_response` on the retried response.

### Task 2: Add tests to test/lib/source_monitor/fetching/feed_fetcher_test.rb

Add 3 tests under a new section `# -- AIA Certificate Resolution --`:

1. **SSL error + AIA resolve succeeds -> fetch succeeds:**
   - First stub: raise `Faraday::SSLError`
   - Stub `AIAResolver.resolve` to return a mock certificate
   - Stub `AIAResolver.enhanced_cert_store` to return a store
   - Second stub (after retry): return 200 with RSS body
   - Assert result.status == :fetched

2. **SSL error + AIA resolve returns nil -> ConnectionError:**
   - Stub to raise `Faraday::SSLError`
   - Stub `AIAResolver.resolve` to return nil
   - Assert result.status == :failed
   - Assert result.error is ConnectionError

3. **Non-SSL ConnectionError -> AIA not attempted:**
   - Stub to raise `Faraday::ConnectionFailed`
   - Verify `AIAResolver.resolve` was NOT called
   - Assert result.status == :failed
   - Assert result.error is ConnectionError

### Task 3: Run full verification

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb`
2. `bin/rails test` (full suite)
3. `bin/rubocop`
4. `bin/brakeman --no-pager`

## Files

| Action | Path |
|--------|------|
| MODIFY | `lib/source_monitor/fetching/feed_fetcher.rb` |
| MODIFY | `test/lib/source_monitor/fetching/feed_fetcher_test.rb` |

## Verification

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb
bin/rails test
bin/rubocop
bin/brakeman --no-pager
```
