---
phase: "02"
plan: "01"
title: "Error Categorization and Blocked Feed Detection"
wave: 1
depends_on: []
must_haves:
  - "BlockedError subclass of FetchError with CODE='blocked'"
  - "HTML body sniffing in FeedFetcher#parse_feed detects Cloudflare/login walls before Feedjira"
  - "error_category string column on FetchLog (network, parse, blocked, auth, unknown)"
  - "SourceUpdater maps error class to error_category when creating fetch logs"
  - "RetryPolicy handles BlockedError with appropriate retry/circuit policy"
  - "Tests for all new error paths"
---

# Plan 01: Error Categorization and Blocked Feed Detection

## Summary

Add structured error categorization to the fetch pipeline. Introduce `BlockedError` for Cloudflare/login wall detection by sniffing HTML response bodies before passing to Feedjira. Add `error_category` column to `FetchLog` for coarse filtering. Update `RetryPolicy` to handle blocked errors appropriately.

## Tasks

### Task 1: Add BlockedError to error hierarchy

**Files to modify:**
- `lib/source_monitor/fetching/fetch_error.rb`

**Steps:**
1. Add `BlockedError < FetchError` with `CODE = "blocked"` after the existing `ParsingError` class
2. Add `AuthenticationError < FetchError` with `CODE = "authentication"` for 401/403 responses that are NOT blocked pages
3. BlockedError should accept an optional `blocked_by` keyword (e.g., "cloudflare", "login_wall", "captcha", "unknown") stored as an attribute

### Task 2: Add HTML body sniffing to detect blocked responses

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher.rb`

**Steps:**
1. Add a new private method `detect_blocked_response(body, response)` that checks the response body BEFORE calling `Feedjira.parse`
2. Detection markers for Cloudflare:
   - `<title>Just a moment</title>` or `<title>Attention Required</title>`
   - `cf-challenge` or `cf-browser-verification` in body
   - `__cf_chl_` in body
   - `data-ray=` attribute (Cloudflare Ray ID)
3. Detection markers for login walls / auth walls:
   - `<title>Log in</title>` or `<title>Sign in</title>` (case-insensitive)
   - Response has `text/html` content-type AND body starts with `<!DOCTYPE html` or `<html` AND contains `<form` with `password` input
4. Detection markers for CAPTCHA:
   - `g-recaptcha` or `h-captcha` in body
5. Modify `parse_feed(body, response)` to call `detect_blocked_response(body, response)` first. If detection returns a blocked_by value, raise `BlockedError` with that value instead of attempting Feedjira parse
6. Keep a size limit on sniffing -- only inspect first 4KB of body to avoid scanning huge feeds

### Task 3: Add error_category column to FetchLog

**Files to create:**
- `db/migrate/TIMESTAMP_add_error_category_to_fetch_logs.rb`

**Files to modify:**
- `app/models/source_monitor/fetch_log.rb`

**Steps:**
1. Create migration adding `error_category` string column to `sourcemon_fetch_logs` (nullable, no default)
2. Add index on `error_category` for filtering
3. In FetchLog model, add validation: `validates :error_category, inclusion: { in: %w[network parse blocked auth unknown], allow_nil: true }`
4. Add scope: `scope :by_category, ->(category) { where(error_category: category) }`
5. Add `error_category` to `ransackable_attributes` if the method exists on FetchLog

### Task 4: Map error classes to categories in SourceUpdater

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

**Steps:**
1. Add a class method or constant `ERROR_CATEGORY_MAP` that maps error classes to category strings:
   - `TimeoutError` -> `"network"`
   - `ConnectionError` -> `"network"`
   - `HTTPError` -> categorize by status: 401/403 -> `"auth"`, others -> `"network"`
   - `ParsingError` -> `"parse"`
   - `BlockedError` -> `"blocked"`
   - `AuthenticationError` -> `"auth"`
   - `UnexpectedResponseError` -> `"unknown"`
   - `FetchError` (base) -> `"unknown"`
2. Add private method `categorize_error(error)` that uses the map
3. Modify `create_fetch_log` to include `error_category: categorize_error(error)` when error is present

### Task 5: Add BlockedError to RetryPolicy

**Files to modify:**
- `lib/source_monitor/fetching/retry_policy.rb`

**Steps:**
1. Add `:blocked` key to `DEFAULTS`: `blocked: { attempts: 1, wait: 1.hour, circuit_wait: 4.hours }` -- blocked feeds are unlikely to resolve quickly, so aggressive circuit break
2. Update `policy_key` method to return `:blocked` for `BlockedError`
3. Add `:authentication` key: `authentication: { attempts: 1, wait: 1.hour, circuit_wait: 4.hours }` -- auth failures also unlikely to self-resolve
4. Update `policy_key` to return `:authentication` for `AuthenticationError`

### Task 6: Update FeedFetcher perform_fetch to re-raise BlockedError

**Files to modify:**
- `lib/source_monitor/fetching/feed_fetcher.rb`

**Steps:**
1. In `perform_fetch`, add `BlockedError` and `AuthenticationError` to the list of errors that are re-raised directly (line 81): `rescue TimeoutError, ConnectionError, HTTPError, ParsingError, BlockedError, AuthenticationError => error`

### Task 7: Tests

**Files to create:**
- `test/lib/source_monitor/fetching/blocked_error_test.rb`
- `test/lib/source_monitor/fetching/html_detection_test.rb`

**Files to modify:**
- `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
- `test/lib/source_monitor/fetching/retry_policy_test.rb`
- `test/lib/source_monitor/fetching/source_updater_test.rb` (or wherever source_updater tests live)
- `test/models/source_monitor/fetch_log_test.rb`

**Steps:**
1. **blocked_error_test.rb**: Test BlockedError has CODE="blocked", accepts blocked_by keyword, inherits from FetchError
2. **html_detection_test.rb**: Test detect_blocked_response with:
   - Cloudflare challenge HTML -> returns "cloudflare"
   - Login wall HTML with password form -> returns "login_wall"
   - CAPTCHA page -> returns "captcha"
   - Valid RSS/Atom XML -> returns nil (no block detected)
   - HTML page without block markers -> returns nil
   - Large body only inspects first 4KB
3. **feed_fetcher_test.rb**: Add test that when HTTP 200 returns CF challenge HTML, result is :failed with BlockedError (not ParsingError)
4. **retry_policy_test.rb**: Add tests for :blocked and :authentication policy keys
5. **source_updater_test.rb**: Test that error_category is correctly set on fetch_log for each error type
6. **fetch_log_test.rb**: Test error_category validation, by_category scope

## Acceptance Criteria

- [ ] Cloudflare challenge HTML (200 OK) raises `BlockedError`, NOT `ParsingError`
- [ ] `FetchLog` records include `error_category` for failed fetches
- [ ] Categories correctly map: network errors -> "network", parse errors -> "parse", CF blocks -> "blocked", 401/403 -> "auth"
- [ ] `RetryPolicy` applies aggressive circuit break (4h) for blocked feeds
- [ ] Valid XML/RSS/Atom feeds are NOT falsely detected as blocked
- [ ] All new code has test coverage
- [ ] `bin/rubocop` passes with zero offenses
- [ ] `bin/rails test` passes
