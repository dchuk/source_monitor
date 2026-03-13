---
phase: "02"
plan: "01"
title: "Error Categorization and Blocked Feed Detection"
status: complete
---

# Plan 01 Summary: Error Categorization and Blocked Feed Detection

## What Was Built

Added structured error categorization to the fetch pipeline with Cloudflare/login wall/CAPTCHA detection. Feeds returning HTML challenge pages at HTTP 200 now correctly raise `BlockedError` instead of misleading `ParsingError`. Fetch logs now include an `error_category` column for coarse filtering. Retry policy applies aggressive circuit break (4h) for blocked and authentication errors.

## Tasks Completed

1. **Add BlockedError to error hierarchy** (Task 1 - pre-existing, commit bb1cbfb)
   - `BlockedError` and `AuthenticationError` subclasses of `FetchError`

2. **Add HTML body sniffing** (Task 2)
   - `detect_blocked_response` inspects first 4KB for Cloudflare, CAPTCHA, and login wall markers
   - Runs before `Feedjira.parse` in `parse_feed`

3. **Add error_category column to FetchLog** (Task 3)
   - Migration adds nullable string column with index
   - Validation restricts to: network, parse, blocked, auth, unknown
   - `by_category` scope for filtering

4. **Map error classes to categories in SourceUpdater** (Task 4)
   - `ERROR_CATEGORY_MAP` constant maps error classes to category strings
   - `categorize_error` handles HTTPError status-based categorization (401/403 -> auth)
   - Sets `error_category` on fetch log creation

5. **Add blocked/authentication to RetryPolicy** (Task 5)
   - `:blocked` and `:authentication` keys: 1 attempt, 1h wait, 4h circuit break
   - `policy_key` routes `BlockedError` and `AuthenticationError` appropriately

6. **Update perform_fetch rescue list** (Task 6)
   - `BlockedError` and `AuthenticationError` added to re-raise list

7. **Tests for all new paths** (Task 7)
   - 55 new tests across 6 files covering all error classes, detection markers, retry policies, category mapping, and integration

## Files Modified

- `lib/source_monitor/fetching/feed_fetcher.rb` - HTML body sniffing, rescue list
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` - error category mapping
- `lib/source_monitor/fetching/retry_policy.rb` - blocked/auth policies
- `app/models/source_monitor/fetch_log.rb` - validation, scope
- `db/migrate/20260306233004_add_error_category_to_fetch_logs.rb` - new migration
- `test/lib/source_monitor/fetching/blocked_error_test.rb` - new
- `test/lib/source_monitor/fetching/html_detection_test.rb` - new
- `test/lib/source_monitor/fetching/retry_policy_test.rb` - new
- `test/lib/source_monitor/fetching/feed_fetcher/source_updater_error_category_test.rb` - new
- `test/lib/source_monitor/fetching/feed_fetcher_error_handling_test.rb` - modified
- `test/models/source_monitor/fetch_log_test.rb` - modified
- `test/dummy/db/schema.rb` - updated by migration

## Commits

| Hash | Message |
|------|---------|
| bb1cbfb | feat(fetching): add BlockedError and AuthenticationError to error hierarchy |
| f291d8f | feat(fetching): add HTML body sniffing for blocked response detection |
| abc07cc | feat(fetch_log): add error_category column for structured error classification |
| 4e88a00 | feat(source_updater): map error classes to error_category on fetch logs |
| 0546128 | feat(retry_policy): add blocked and authentication retry policies |
| fe3d812 | test(fetching): add tests for error categorization and blocked detection |

## Deviations

- None. All tasks implemented as planned.

## Verification

- `bin/rubocop` on all modified files: 0 offenses
- `bin/rails test`: 1304 runs, 3951 assertions, 0 failures, 0 errors, 0 skips
