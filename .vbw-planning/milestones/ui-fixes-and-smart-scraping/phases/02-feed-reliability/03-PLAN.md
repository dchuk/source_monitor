---
phase: "02"
plan: "03"
title: "Cloudflare Light Bypass Techniques"
wave: 2
depends_on: ["01"]
must_haves:
  - "UA rotation from a curated list of real browser UAs"
  - "Cookie persistence across retry attempt (re-request with Set-Cookie from initial response)"
  - "If all bypass attempts fail, raise BlockedError with diagnostic details"
  - "Source shows 'Cloudflare Blocked' badge when last error is BlockedError"
  - "Tests for bypass attempts and fallback to BlockedError"
---

# Plan 03: Cloudflare Light Bypass Techniques

## Summary

Before giving up on a Cloudflare-challenged feed, attempt light bypass techniques: UA rotation, cookie persistence, and alternate request headers. If all fail, raise BlockedError (from Plan 01) with clear diagnostics. Show a "Blocked" badge on the source UI.

## Tasks

### Task 1: Create CloudflareBypass module

**Files to create:**
- `lib/source_monitor/fetching/cloudflare_bypass.rb`

**Steps:**
1. Create `SourceMonitor::Fetching::CloudflareBypass` class
2. Initialize with `response:` (the initial blocked response) and `feed_url:`
3. `#call` method tries bypass strategies in order, returns the successful response or nil:
   a. **Cookie replay**: Extract `Set-Cookie` headers from initial response, re-request with those cookies set
   b. **UA rotation**: Try 3-4 different real browser UA strings (Chrome, Firefox, Safari, Edge -- recent versions)
   c. **Cache-busting headers**: Add `Cache-Control: no-cache`, `Pragma: no-cache` headers
4. Each attempt uses `SourceMonitor::HTTP.client` with modified headers
5. After each attempt, check if the response body still contains Cloudflare markers (reuse detection logic from Plan 01). If markers gone, return the response.
6. If all strategies fail, return nil
7. Add a constant `USER_AGENTS` with 4-5 curated, real browser UA strings

### Task 2: Integrate CloudflareBypass into FeedFetcher

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher.rb`

**Steps:**
1. In `parse_feed`, after `detect_blocked_response` identifies a Cloudflare block (blocked_by == "cloudflare"):
   - Before raising BlockedError, attempt `CloudflareBypass.new(response:, feed_url: source.feed_url).call`
   - If bypass returns a successful response, use that response's body for `Feedjira.parse`
   - If bypass returns nil, raise `BlockedError` as before
2. Only attempt bypass for Cloudflare blocks (not login walls or CAPTCHAs -- those won't be solved by header changes)
3. Add a guard to prevent infinite loops: if `@bypass_attempted` is set, skip bypass

### Task 3: Add "Blocked" badge to source UI

**Files to modify:**
- `app/views/source_monitor/sources/_details.html.erb` (or wherever source status badges are rendered)
- `app/views/source_monitor/sources/_row.html.erb` (list view)

**Steps:**
1. Check if source's `last_error` contains "blocked" or if latest fetch_log has `error_category == "blocked"`
2. Show a red/orange "Blocked" badge next to the source name/status
3. Use existing badge styling patterns from health_status badges
4. Badge should include a tooltip or title attribute with the blocked_by detail (e.g., "Cloudflare Blocked")
5. Keep it simple -- use the `last_error` field which already stores the error message, and check for the BlockedError class name in the latest fetch_log's `error_class`

### Task 4: Tests

**Files to create:**
- `test/lib/source_monitor/fetching/cloudflare_bypass_test.rb`

**Files to modify:**
- `test/lib/source_monitor/fetching/feed_fetcher_test.rb`

**Steps:**
1. **cloudflare_bypass_test.rb**:
   - Test cookie replay: stub initial response with Set-Cookie, verify retry includes cookies
   - Test UA rotation: verify different UA strings are tried
   - Test successful bypass: when one strategy returns non-CF response, returns it
   - Test all strategies fail: returns nil
   - Test only makes HTTP requests (use WebMock stubs)
2. **feed_fetcher_test.rb**:
   - Test that Cloudflare block triggers bypass attempt before raising BlockedError
   - Test that successful bypass proceeds to parse the new response
   - Test that failed bypass raises BlockedError with blocked_by="cloudflare"
   - Test that non-Cloudflare blocks (login wall) do NOT attempt bypass
3. **View tests** (if system tests exist for source details):
   - Test that blocked source shows "Blocked" badge
   - Test that non-blocked source does not show badge

## Acceptance Criteria

- [ ] Cloudflare-blocked feeds attempt light bypass before failing
- [ ] At least cookie replay and UA rotation are attempted
- [ ] Successful bypass proceeds to normal feed parsing
- [ ] Failed bypass raises BlockedError with diagnostic info
- [ ] Source UI shows "Blocked" badge for blocked feeds
- [ ] Bypass does not apply to non-Cloudflare blocks (login walls, CAPTCHAs)
- [ ] All HTTP requests in bypass are properly mocked in tests
- [ ] `bin/rubocop` passes with zero offenses
- [ ] `bin/rails test` passes
