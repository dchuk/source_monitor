---
phase: "04"
plan: "03"
title: "Sources Index Scrape Recommendation Badge"
status: complete
---

## What Was Built

Scrape recommendation badge on source rows in the sources index. Sources with avg feed words below threshold and scraping disabled show a "Scrape Recommended" badge. Also added `avg_feed_words_lt` filter support for the dashboard widget link.

## Commits

| Hash | Message |
|------|---------|
| 1ebfadc | feat(sources): add scrape recommendation badge and avg_feed_words_lt filter |

## Tasks Completed

1. **Compute scrape candidate IDs in SourcesController#index** -- Added `@scrape_candidate_ids` Set computed from loaded sources and avg word counts.
2. **Add scrape recommendation badge to source row partial** -- Violet badge with tooltip, appears only for candidates.
3. **Update sources index to pass candidate IDs to row partial** -- Added `scrape_candidate_ids` to locals.
4. **Add avg_feed_words_lt filter label to sources index** -- Filter pill shows when dashboard link is clicked.

## Files Modified

- `app/controllers/source_monitor/sources_controller.rb`
- `app/views/source_monitor/sources/_row.html.erb`
- `app/views/source_monitor/sources/index.html.erb`
- `test/controllers/source_monitor/sources_controller_test.rb`

## Deviations

- All 4 tasks committed in a single commit since they form a cohesive feature with tightly coupled files.
