---
phase: 1
plan: 1
title: "HTTP Client Hardening"
wave: 1
depends_on: []
must_haves:
  - DEFAULT_USER_AGENT changed to "Mozilla/5.0 (compatible; SourceMonitor/VERSION)" in http.rb
  - HTTPSettings#default_user_agent returns same polite-bot string
  - Accept header prepends text/html
  - Accept-Language and DNT headers added to default_headers
  - FeedFetcher#request_headers sends Referer from source.website_url
  - All existing http_test.rb assertions updated for new header values
  - New tests for Accept-Language, DNT, and Referer headers
  - bin/rails test passes, bin/rubocop zero offenses
---

# Plan 01: HTTP Client Hardening

## Objective

Update default HTTP headers to reduce bot-blocking: browser-like User-Agent, broader Accept, Accept-Language, DNT, and per-source Referer header.

## Context

- `@lib/source_monitor/http.rb` -- DEFAULT_USER_AGENT (line 17), default_headers (lines 89-97)
- `@lib/source_monitor/configuration/http_settings.rb` -- default_user_agent (lines 44-46)
- `@lib/source_monitor/fetching/feed_fetcher.rb` -- request_headers (lines 104-111)
- `@test/lib/source_monitor/http_test.rb` -- header assertions (lines 92-97, 111)

REQ-UA-01: Change default User-Agent from "SourceMonitor/VERSION" to a browser-like string.

## Tasks

### Task 1: Update User-Agent default

**Files:** `lib/source_monitor/http.rb`, `lib/source_monitor/configuration/http_settings.rb`

1. In `http.rb` line 17, change `DEFAULT_USER_AGENT` to `"Mozilla/5.0 (compatible; SourceMonitor/#{SourceMonitor::VERSION})"`
2. In `http_settings.rb` line 45, update `default_user_agent` to return the same string: `"Mozilla/5.0 (compatible; SourceMonitor/#{SourceMonitor::VERSION})"`

### Task 2: Add Accept-Language, DNT, and broader Accept

**Files:** `lib/source_monitor/http.rb`

In `default_headers` method (lines 89-97):
1. Change Accept value to: `"text/html, application/rss+xml, application/atom+xml, application/json;q=0.9, text/xml;q=0.8"`
2. Add `"Accept-Language" => "en-US,en;q=0.9"`
3. Add `"DNT" => "1"`

### Task 3: Add Referer header in FeedFetcher

**Files:** `lib/source_monitor/fetching/feed_fetcher.rb`

In `request_headers` method (lines 104-111), after transforming custom_headers:
- Add `headers["Referer"] = source.website_url if source.website_url.present?`
- Must go before the conditional cache headers so per-source custom_headers can still override

### Task 4: Update existing tests and add new tests

**Files:** `test/lib/source_monitor/http_test.rb`, `test/lib/source_monitor/fetching/feed_fetcher_test.rb`

In `http_test.rb`:
1. Update "allows overriding headers while preserving defaults" (line 96) -- Assert new Accept value with `text/html` prefix
2. Add test: "includes Accept-Language and DNT in default headers" -- assert `en-US,en;q=0.9` and `"1"`
3. Add test: "default user agent is browser-like" -- assert includes `Mozilla/5.0` and `SourceMonitor/`

In `feed_fetcher_test.rb` (or create new test section):
1. Add test: "request_headers includes Referer from source website_url" -- create source with website_url, verify Referer in headers
2. Add test: "request_headers omits Referer when website_url is blank" -- create source without website_url, verify no Referer

## Files

| Action | Path |
|--------|------|
| MODIFY | `lib/source_monitor/http.rb` |
| MODIFY | `lib/source_monitor/configuration/http_settings.rb` |
| MODIFY | `lib/source_monitor/fetching/feed_fetcher.rb` |
| MODIFY | `test/lib/source_monitor/http_test.rb` |
| MODIFY | `test/lib/source_monitor/fetching/feed_fetcher_test.rb` |

## Verification

```bash
bin/rails test test/lib/source_monitor/http_test.rb test/lib/source_monitor/fetching/feed_fetcher_test.rb
bin/rubocop lib/source_monitor/http.rb lib/source_monitor/configuration/http_settings.rb lib/source_monitor/fetching/feed_fetcher.rb
```

## Success Criteria

- Default UA contains `Mozilla/5.0` and `SourceMonitor/`
- Accept header starts with `text/html`
- Accept-Language and DNT present in every default request
- Referer sent when source has website_url, omitted when blank
- Per-source custom_headers still override all defaults
- All tests pass, zero RuboCop offenses
