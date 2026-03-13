---
phase: "02"
plan: "03"
title: "Cloudflare Light Bypass Techniques"
status: complete
---

# Plan 03 Summary: Cloudflare Light Bypass Techniques

## What Was Built

Before giving up on a Cloudflare-challenged feed, the FeedFetcher now attempts light bypass techniques: cookie replay from Set-Cookie headers, UA rotation through 4 real browser strings (Chrome, Safari, Firefox, Edge), and cache-busting headers on every attempt. If all strategies fail, BlockedError is raised as before. Non-Cloudflare blocks (login walls, CAPTCHAs) skip bypass entirely.

The source UI now shows a "Blocked" badge (rose-colored) next to the source name when the last error indicates a blocked feed, with a tooltip showing the blocker identity (e.g., "Cloudflare Blocked").

## Tasks Completed

1. **CloudflareBypass module** -- Created `SourceMonitor::Fetching::CloudflareBypass` service with cookie replay, UA rotation (4 real browser UAs), and cache-busting headers. Returns successful response or nil.
2. **FeedFetcher integration** -- Modified `parse_feed` to attempt CloudflareBypass when `detect_blocked_response` identifies a Cloudflare block. Guard flag prevents infinite loops. Non-Cloudflare blocks skip bypass.
3. **Blocked badge in UI** -- Added rose-colored "Blocked" badge to `_details.html.erb` and `_row.html.erb` with `data-testid="source-blocked-badge"` and tooltip showing blocker identity.
4. **Tests** -- 15 new tests: 8 CloudflareBypass unit tests, 4 FeedFetcher bypass integration tests, 3 controller tests for blocked badge display.

## Files Modified

- `lib/source_monitor/fetching/cloudflare_bypass.rb` (created)
- `lib/source_monitor/fetching/feed_fetcher.rb` (modified: bypass integration in parse_feed)
- `lib/source_monitor.rb` (modified: added autoload for CloudflareBypass)
- `app/views/source_monitor/sources/_details.html.erb` (modified: blocked badge)
- `app/views/source_monitor/sources/_row.html.erb` (modified: blocked badge)
- `test/lib/source_monitor/fetching/cloudflare_bypass_test.rb` (created)
- `test/lib/source_monitor/fetching/feed_fetcher_error_handling_test.rb` (modified: 4 bypass integration tests)
- `test/controllers/source_monitor/sources_controller_test.rb` (modified: 3 badge tests)

## Commits

- `ff36cdf` feat(fetching): add CloudflareBypass module with cookie replay and UA rotation
- `0084079` feat(fetching): integrate CloudflareBypass into FeedFetcher parse_feed
- `e0fceff` feat(ui): add Blocked badge to source detail and row views
- `ad76971` test(fetching): add CloudflareBypass and blocked badge tests

## Deviations

None. All tasks completed as planned.

## Test Results

- 1329 runs, 4024 assertions, 0 failures, 0 errors, 0 skips
- RuboCop: 0 offenses on all modified files
