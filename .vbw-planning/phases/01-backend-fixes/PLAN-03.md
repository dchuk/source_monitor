---
phase: 1
plan: 3
title: "Remove Default Scrape Limit"
wave: 1
depends_on: []
must_haves:
  - DEFAULT_MAX_IN_FLIGHT changed from 25 to nil in scraping_settings.rb
  - ScrapingSettings#reset! sets @max_in_flight_per_source to nil
  - Existing rate_limit_exhausted? already handles nil (returns [false, nil])
  - BulkResultPresenter rate_limited message only shows limit when non-nil (already correct)
  - Tests that relied on default 25 updated to explicitly set a limit
  - New test confirms default max_in_flight_per_source is nil
  - bin/rails test passes, bin/rubocop zero offenses
---

# Plan 03: Remove Default Scrape Limit

## Objective

Remove the default per-source scrape limit (was 25) so Solid Queue's worker pool provides natural backpressure. Users who want a cap can still set `config.scraping.max_in_flight_per_source`.

## Context

- `@lib/source_monitor/configuration/scraping_settings.rb` -- DEFAULT_MAX_IN_FLIGHT = 25 (line 8), reset! (line 16)
- `@lib/source_monitor/scraping/enqueuer.rb` -- rate_limit_exhausted? (lines 108-114), returns early if limit is nil
- `@lib/source_monitor/scraping/bulk_result_presenter.rb` -- line 58: shows limit only if non-nil
- `@test/lib/source_monitor/scraping/bulk_source_scraper_test.rb` -- "respects per-source rate limit" (line 88)
- `@test/lib/source_monitor/scraping/enqueuer_test.rb` -- "enforces per-source in-flight rate limit" (line 71)

REQ-SL-01: Refine max_in_flight_per_source to only count actively-running scrape jobs (not queued ones).

**Decision:** Simpler approach -- remove the default limit entirely (set to nil). The rate_limit_exhausted? method, BulkResultPresenter, and BulkSourceScraper already handle nil correctly by skipping the check.

## Tasks

### Task 1: Change default to nil

**Files:** `lib/source_monitor/configuration/scraping_settings.rb`

1. Change line 8: `DEFAULT_MAX_IN_FLIGHT = nil` (was 25)
2. The `reset!` method at line 16 already uses `DEFAULT_MAX_IN_FLIGHT`, so it will pick up nil automatically

No other code changes needed -- `Enqueuer#rate_limit_exhausted?` returns `[false, nil]` when limit is nil (line 110), `BulkResultPresenter` only shows the limit message when limit is non-nil (line 58).

### Task 2: Update tests that assumed default was 25

**Files:** `test/lib/source_monitor/scraping/bulk_source_scraper_test.rb`, `test/lib/source_monitor/scraping/enqueuer_test.rb`

Review tests that rely on the default limit:

1. In `bulk_source_scraper_test.rb` "respects per-source rate limit" (line 88): Already explicitly sets `config.scraping.max_in_flight_per_source = 2` -- **no change needed**
2. In `enqueuer_test.rb` "enforces per-source in-flight rate limit" (line 71): Already explicitly sets `config.scraping.max_in_flight_per_source = 1` -- **no change needed**
3. In `bulk_source_scraper_test.rb` "determine_status returns :partial" (line 307): Already explicitly sets `config.scraping.max_in_flight_per_source = 2` -- **no change needed**

All rate-limit tests already set explicit limits -- the default value change has no impact on them.

### Task 3: Add new test for nil default

**Files:** `test/lib/source_monitor/scraping/enqueuer_test.rb`

Add test:
1. **"does not rate-limit when default max_in_flight is nil"**
   - Create source with scraping_enabled, create many items with `pending` status (e.g., 30)
   - Create one more eligible item with nil scrape_status
   - Do NOT configure any explicit limit (rely on default nil)
   - Enqueue via `Enqueuer.enqueue(item: eligible_item)`
   - Assert result is `:enqueued` (not rate_limited)

2. **"rate-limits when user explicitly sets max_in_flight_per_source"**
   - This test already exists (line 71) but add a comment clarifying it's opt-in

### Task 4: Verify BulkResultPresenter handles nil limit

**Files:** `test/lib/source_monitor/scraping/bulk_result_presenter_test.rb`

Check existing tests. If no test covers the rate_limited path with a nil limit:
1. Add test: "partial payload shows generic limit message when limit is nil" -- build a BulkSourceScraper::Result with `rate_limited: true`, construct presenter, verify message says "Stopped after reaching the per-source limit" without a number suffix

## Files

| Action | Path |
|--------|------|
| MODIFY | `lib/source_monitor/configuration/scraping_settings.rb` |
| MODIFY | `test/lib/source_monitor/scraping/enqueuer_test.rb` |
| MODIFY | `test/lib/source_monitor/scraping/bulk_result_presenter_test.rb` |

## Verification

```bash
bin/rails test test/lib/source_monitor/scraping/enqueuer_test.rb test/lib/source_monitor/scraping/bulk_source_scraper_test.rb test/lib/source_monitor/scraping/bulk_result_presenter_test.rb
bin/rubocop lib/source_monitor/configuration/scraping_settings.rb
```

## Success Criteria

- `ScrapingSettings.new.max_in_flight_per_source` returns nil by default
- With nil limit, Enqueuer does not rate-limit any enqueues
- Explicit user-configured limit still works as before
- BulkResultPresenter handles nil limit in rate_limited message
- All scraping tests pass, zero RuboCop offenses
