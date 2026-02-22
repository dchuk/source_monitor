---
phase: 5
plan: 2
title: Per-Source Scrape Rate Limiting
wave: 1
depends_on: []
must_haves:
  - "migration adds min_scrape_interval column (decimal, seconds) to sourcemon_sources with default nil"
  - "ScrapingSettings has min_scrape_interval attribute with DEFAULT_MIN_SCRAPE_INTERVAL = 1.0 (seconds)"
  - "Enqueuer derives last-scrape timestamp from scrape_logs MAX(started_at) per source"
  - "when rate-limited, ScrapeItemJob re-enqueues itself with set(wait:) for remaining interval"
  - "per-source min_scrape_interval overrides global ScrapingSettings.min_scrape_interval when present"
  - "all existing enqueuer and scrape_item_job tests pass, new tests cover rate limit behavior"
  - "RuboCop zero offenses"
skills_used:
  - sm-engine-migration
  - sm-configuration-setting
---

## Objective

Add time-based per-source scrape rate limiting. The system derives the last scrape timestamp from `scrape_logs MAX(started_at)` per source. When a scrape is attempted too soon, the job re-enqueues itself with a delay equal to the remaining interval. Each source can override the global minimum interval via a new `min_scrape_interval` column.

## Context

- `@` `lib/source_monitor/scraping/enqueuer.rb` -- current rate limiting checks in-flight count only; need to add time-based check
- `@` `lib/source_monitor/configuration/scraping_settings.rb` -- current settings: max_in_flight_per_source, max_bulk_batch_size
- `@` `app/jobs/source_monitor/scrape_item_job.rb` -- performs scrape; needs re-enqueue-with-delay logic
- `@` `app/models/source_monitor/scrape_log.rb` -- has started_at column, belongs_to source
- `@` `app/models/source_monitor/source.rb` -- will get min_scrape_interval column (but model file not modified -- just migration)
- `@` `.claude/skills/sm-engine-migration/SKILL.md` -- migration conventions (sourcemon_ prefix)
- `@` `.claude/skills/sm-configuration-setting/SKILL.md` -- config setting conventions

## Tasks

### Task 1: Add min_scrape_interval column to sources

**Files:** `db/migrate/TIMESTAMP_add_min_scrape_interval_to_sources.rb`

Create migration adding `min_scrape_interval` (decimal, precision: 10, scale: 2, null: true, default: nil) to `sourcemon_sources`. No index needed -- this is a per-record configuration value, not a query filter. The nil default means "use global setting".

### Task 2: Add min_scrape_interval to ScrapingSettings

**Files:** `lib/source_monitor/configuration/scraping_settings.rb`

Add `attr_accessor :min_scrape_interval` with `DEFAULT_MIN_SCRAPE_INTERVAL = 1.0` (seconds). Add setter with `normalize_numeric` validation (same pattern as existing settings). Reset to default in `reset!`. This is the global fallback when a source's `min_scrape_interval` is nil.

### Task 3: Add time-based rate check to Enqueuer

**Files:** `lib/source_monitor/scraping/enqueuer.rb`

Add private method `time_rate_limited?` that:
1. Resolves effective interval: `source.min_scrape_interval || SourceMonitor.config.scraping.min_scrape_interval`
2. Returns `[false, nil]` if interval is nil or <= 0
3. Queries `source.scrape_logs.maximum(:started_at)` for last scrape time
4. Returns `[false, nil]` if no prior scrape
5. Calculates `elapsed = Time.current - last_scrape_at`
6. If `elapsed < interval`: returns `[true, { wait_seconds: (interval - elapsed).ceil, interval:, last_scrape_at: }]`
7. Otherwise returns `[false, nil]`

In `#enqueue`, call `time_rate_limited?` AFTER the existing `rate_limit_exhausted?` check (inside the lock block). If rate-limited, set `time_limited = true` and `time_limit_info`.

After the lock block, if `time_limited`: instead of returning a failure, re-enqueue the job with delay via `job_class.set(wait: info[:wait_seconds].seconds).perform_later(item.id)` and return a new Result with `status: :deferred` and descriptive message. Add `deferred?` method to Result struct.

### Task 4: Add re-enqueue with delay to ScrapeItemJob

**Files:** `app/jobs/source_monitor/scrape_item_job.rb`

Modify `#perform` to check time-based rate limit before scraping. Add early check: resolve effective interval, query `source.scrape_logs.maximum(:started_at)`, calculate elapsed. If too soon: clear in-flight state, re-enqueue self with `self.class.set(wait: remaining.seconds).perform_later(item_id)`, log the deferral, and return early. This ensures even directly-enqueued jobs (bypassing Enqueuer) respect rate limits.

### Task 5: Write rate limiting tests

**Files:** `test/lib/source_monitor/scraping/enqueuer_test.rb`, `test/jobs/source_monitor/scrape_item_job_test.rb`

Enqueuer tests: (1) allows scrape when no prior scrape exists, (2) allows scrape when elapsed > interval, (3) returns deferred status when elapsed < interval with correct wait_seconds, (4) per-source interval overrides global, (5) nil/zero interval disables time rate limiting, (6) deferred result re-enqueues job with delay.

ScrapeItemJob tests: (1) performs scrape when not rate-limited, (2) re-enqueues with delay when rate-limited, (3) clears in-flight state on deferral.

Run full test suite to verify no regressions.

## Verification

```bash
bin/rails test test/lib/source_monitor/scraping/enqueuer_test.rb test/jobs/source_monitor/scrape_item_job_test.rb
bin/rails test
bin/rubocop lib/source_monitor/scraping/enqueuer.rb lib/source_monitor/configuration/scraping_settings.rb app/jobs/source_monitor/scrape_item_job.rb
```

## Success Criteria

- Per-source scrape rate limiting derives last-scrape from scrape_logs MAX(started_at)
- When rate-limited, job is re-enqueued with delay (remaining interval)
- Source.min_scrape_interval overrides global ScrapingSettings.min_scrape_interval
- Default global interval is 1 second
- Nil/zero interval disables time rate limiting
- All tests pass, RuboCop zero offenses
