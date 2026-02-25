---
phase: 5
plan: 2
status: complete
tasks_completed: 5
tasks_total: 5
commits:
  - hash: 5f4b47f
    message: "feat(05-p2): add min_scrape_interval column to sources"
  - hash: af7575e
    message: "feat(05-p2): add min_scrape_interval to ScrapingSettings"
  - hash: 2d9d21b
    message: "feat(05-p2): add time-based rate check to Enqueuer"
  - hash: b68828b
    message: "feat(05-p2): add time-based rate limit check to ScrapeItemJob"
  - hash: 8007eb7
    message: "test(05-p2): add time-based rate limiting tests"
deviations: []
---

## What Was Built

- Per-source scrape rate limiting via min_scrape_interval column on sourcemon_sources
- Global default interval (1.0s) in ScrapingSettings with per-source override
- Enqueuer derives last-scrape from scrape_logs MAX(started_at), returns deferred status with re-enqueue
- ScrapeItemJob early rate limit check before scraping, re-enqueues with delay on deferral
- 9 new tests (6 Enqueuer + 3 ScrapeItemJob) covering all rate limit scenarios

## Files Modified

- `db/migrate/20260222120000_add_min_scrape_interval_to_sources.rb` -- new migration
- `test/dummy/db/schema.rb` -- schema updated with min_scrape_interval column
- `lib/source_monitor/configuration/scraping_settings.rb` -- min_scrape_interval attr, DEFAULT, normalize_numeric_float
- `lib/source_monitor/scraping/enqueuer.rb` -- time_rate_limited?, deferred Result status, re-enqueue with delay
- `app/jobs/source_monitor/scrape_item_job.rb` -- time_until_scrape_allowed, early deferral check
- `test/lib/source_monitor/scraping/enqueuer_test.rb` -- 6 new time rate limiting tests
- `test/jobs/source_monitor/scrape_item_job_test.rb` -- 3 new time rate limiting tests
