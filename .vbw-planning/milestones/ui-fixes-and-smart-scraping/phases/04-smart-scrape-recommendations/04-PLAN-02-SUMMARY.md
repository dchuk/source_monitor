---
phase: "04"
plan: "02"
title: "Dashboard Scrape Recommendations Widget"
status: complete
---

## What Was Built

Dashboard widget showing count of scrape candidate sources with a link to the filtered sources index. Widget only renders when candidates exist. Added `scrape_candidates_count` to StatsQuery, created widget partial, wired into dashboard index, and added `scraping_enabled` to ransackable attributes.

## Commits

| Hash | Message |
|------|---------|
| 84da56e | feat(dashboard): add scrape_candidates_count to StatsQuery |
| f33b811 | feat(dashboard): add scrape recommendations widget partial |
| aa25708 | feat(dashboard): wire scrape recommendations widget into dashboard |
| 6de13fa | feat(model): add scraping_enabled to ransackable_attributes |

## Tasks Completed

1. **Add scrape_recommendations to StatsQuery** -- Added `scrape_candidates_count` to stats hash using ScrapeRecommendations query.
2. **Create dashboard scrape recommendations widget partial** -- Card with count, description, and "View Candidates" link.
3. **Wire widget into dashboard index** -- Controller assigns count and threshold, view renders conditionally.
4. **Add scraping_enabled to ransackable_attributes** -- Enables Ransack filter from dashboard link.

## Files Modified

- `lib/source_monitor/dashboard/queries/stats_query.rb`
- `app/views/source_monitor/dashboard/_scrape_recommendations.html.erb` (new)
- `app/controllers/source_monitor/dashboard_controller.rb`
- `app/views/source_monitor/dashboard/index.html.erb`
- `app/models/source_monitor/source.rb`
- `test/controllers/source_monitor/dashboard_controller_test.rb`
- `test/lib/source_monitor/dashboard/stats_query_test.rb`
- `test/lib/source_monitor/dashboard/queries_test.rb`

## Deviations

None.
