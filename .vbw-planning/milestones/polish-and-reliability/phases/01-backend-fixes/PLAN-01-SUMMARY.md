---
phase: 1
plan: 1
title: "HTTP Client Hardening"
status: complete
tasks_completed: 4
tasks_total: 4
commits:
  - bcb2767
  - ff17f0c
  - a647253
  - b3852ef
tests_passed: 52
tests_failed: 0
rubocop_offenses: 0
---

## What Was Built

- Updated DEFAULT_USER_AGENT to `Mozilla/5.0 (compatible; SourceMonitor/VERSION)` in both `http.rb` and `http_settings.rb`
- Added `Accept-Language: en-US,en;q=0.9` and `DNT: 1` to default headers
- Broadened Accept header to prepend `text/html`
- Added Referer header from `source.website_url` in FeedFetcher#request_headers
- Updated existing Accept assertion and added 4 new tests (UA, Accept-Language/DNT, Referer present, Referer blank)

## Files Modified

- `lib/source_monitor/http.rb` -- DEFAULT_USER_AGENT constant, default_headers method
- `lib/source_monitor/configuration/http_settings.rb` -- default_user_agent method
- `lib/source_monitor/fetching/feed_fetcher.rb` -- request_headers method (Referer)
- `test/lib/source_monitor/http_test.rb` -- updated Accept assertion, added UA/header tests
- `test/lib/source_monitor/fetching/feed_fetcher_utilities_test.rb` -- added Referer tests
