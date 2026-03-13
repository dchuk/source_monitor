---
phase: "04"
plan: "01"
title: "Configuration + Model Scope + Scrape Candidate Query"
status: complete
---

## What Was Built

Backend foundation for smart scrape recommendations: a configurable word count threshold (`scrape_recommendation_threshold` defaulting to 200), a `Source.scrape_candidates` scope that identifies active sources with low feed word counts and scraping disabled, and an `Analytics::ScrapeRecommendations` query object that wraps the scope with memoized `candidates_count`, `candidate_ids`, and `candidate?` methods for use by the dashboard and sources index.

## Commits

| Hash | Message |
|------|---------|
| 7785805 | feat(config): add scrape_recommendation_threshold to ScrapingSettings |
| 74ce1bc | feat(model): add Source.scrape_candidates scope |
| 09389ae | feat(analytics): add ScrapeRecommendations query object |

## Tasks Completed

1. **Add scrape_recommendation_threshold to ScrapingSettings** -- Added `DEFAULT_SCRAPE_RECOMMENDATION_THRESHOLD = 200` constant, `attr_accessor`, reset in `reset!`, and setter with `normalize_numeric`. 6 tests.
2. **Add Source.scrape_candidates scope** -- Class method that returns active sources with scraping disabled whose avg feed_word_count is below threshold. Uses subquery with HAVING AVG clause. 7 tests.
3. **Create Analytics::ScrapeRecommendations query object** -- Query class with `candidates_count`, `candidate_ids`, and `candidate?` methods. Memoized results. 6 tests.
4. **Register autoload for ScrapeRecommendations** -- Added `autoload :ScrapeRecommendations` to the Analytics module in `lib/source_monitor.rb`.

## Files Modified

- `lib/source_monitor/configuration/scraping_settings.rb` -- Added threshold constant, attr_accessor, reset, setter
- `app/models/source_monitor/source.rb` -- Added `scrape_candidates` class method
- `lib/source_monitor/analytics/scrape_recommendations.rb` -- New query object
- `lib/source_monitor.rb` -- Added autoload declaration
- `test/lib/source_monitor/configuration_test.rb` -- 6 new tests
- `test/models/source_monitor/source_test.rb` -- 7 new tests
- `test/lib/source_monitor/analytics/scrape_recommendations_test.rb` -- 6 new tests (new file)

## Deviations

- Tasks 3 and 4 were committed together since the autoload registration (Task 4) is required for the query object tests (Task 3) to resolve the class name.
- Test data creates ItemContent via `SourceMonitor::ItemContent.create!(item: item)` with `content` set on the Item, since `feed_word_count` is computed from `item.content` in a `before_save` callback on ItemContent.
