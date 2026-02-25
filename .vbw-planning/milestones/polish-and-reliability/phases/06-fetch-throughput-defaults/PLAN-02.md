---
phase: 6
plan: 2
title: Fixed-Interval Jitter
wave: 1
depends_on: []
must_haves:
  - "fixed-interval path in AdaptiveInterval#apply_adaptive_interval! applies jitter via jitter_percent_value (not hardcoded zero)"
  - "fixed-interval sources get ±jitter_percent variation on next_fetch_at (default 10%)"
  - "jitter_proc override still works for fixed-interval path (test injection)"
  - "existing adaptive interval tests still pass unchanged"
  - "RuboCop zero offenses on changed files"
skills_used: []
---

## Objective

Wire the fixed-interval scheduling path to use the existing `jitter_percent` configuration instead of scheduling at exact intervals. Currently, `apply_adaptive_interval!` line 31-33 sets `next_fetch_at = Time.current + fixed_minutes.minutes` with zero jitter, causing thundering herd effects when many sources share the same interval. REQ-FT-04.

## Context

- `@` `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` -- line 31-33: fixed-interval path has no jitter; line 53-67: `adjusted_interval_with_jitter` and `jitter_offset` already exist for adaptive path
- `@` `lib/source_monitor/configuration/fetching_settings.rb` -- `jitter_percent` already configurable (default 0.1), REQ-FT-08 already satisfied
- `@` `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` -- existing tests use `jitter: ->(_) { 0 }` to zero out jitter for deterministic assertions

## Tasks

### 06-02-T1: Wire fixed-interval path to use jitter

**Files:** `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb`

In the `else` branch of `apply_adaptive_interval!` (fixed-interval path, line 31-33), change from:
```ruby
fixed_minutes = [source.fetch_interval_minutes.to_i, 1].max
attributes[:next_fetch_at] = Time.current + fixed_minutes.minutes
```
to:
```ruby
fixed_minutes = [source.fetch_interval_minutes.to_i, 1].max
fixed_seconds = fixed_minutes * 60.0
attributes[:next_fetch_at] = Time.current + adjusted_interval_with_jitter(fixed_seconds)
```

This reuses the existing `adjusted_interval_with_jitter` method which already calls `jitter_offset` (which respects `jitter_proc` injection and `jitter_percent_value` from config). No new methods needed.

**Acceptance:** The fixed-interval path calls `adjusted_interval_with_jitter` instead of adding exact minutes.

### 06-02-T2: Write tests for fixed-interval jitter

**Files:** `test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb`

Add tests: (1) "fixed-interval sources get jitter when jitter_percent is non-zero" -- create a source with adaptive_fetching_enabled=false and fetch_interval_minutes=60, fetch with default jitter (no jitter proc override), verify next_fetch_at is NOT exactly Time.current + 60.minutes (has some offset within ±10%). (2) "fixed-interval jitter respects jitter_proc override" -- use `jitter: ->(interval) { interval * 0.05 }`, verify next_fetch_at equals Time.current + (60*60 + 60*60*0.05) seconds. (3) "fixed-interval with zero jitter_percent has no jitter" -- configure `config.fetching.jitter_percent = 0`, verify next_fetch_at is exactly Time.current + 60.minutes.

Note: Existing tests that use `jitter: ->(_) { 0 }` will continue to pass unchanged since they explicitly zero out jitter.

**Acceptance:** All new and existing adaptive interval tests pass. `bin/rails test test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb` exits 0.

## Verification

```bash
bin/rails test test/lib/source_monitor/fetching/feed_fetcher_adaptive_interval_test.rb
bin/rubocop lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb
```

## Success Criteria

- Fixed-interval sources get ±10% jitter on next_fetch_at by default
- Jitter uses existing config `jitter_percent` (default 0.1)
- `jitter_proc` injection still overrides for test determinism
- Zero jitter_percent produces exact interval (no randomness)
- All existing adaptive interval tests pass unchanged
- RuboCop zero offenses
