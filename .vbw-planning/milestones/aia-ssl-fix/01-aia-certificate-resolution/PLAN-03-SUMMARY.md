---
phase: 1
plan: 3
status: complete
commit: 9c38bc3
---

## What Was Built
- Wired AIA certificate resolution into FeedFetcher's SSL error handling
- On `Faraday::SSLError`, attempts intermediate cert recovery via `AIAResolver.resolve` before raising
- Guard flag `@aia_attempted` prevents infinite recursion; `rescue StandardError => nil` ensures recovery never makes things worse
- Tags `instrumentation_payload[:aia_resolved] = true` on successful AIA recovery
- 3 integration tests: success retry path, nil fallback to ConnectionError, non-SSL skip

## Files Modified
- `lib/source_monitor/fetching/feed_fetcher.rb` — split SSL rescue, add `attempt_aia_recovery`
- `test/lib/source_monitor/fetching/feed_fetcher_test.rb` — 3 AIA resolution tests
