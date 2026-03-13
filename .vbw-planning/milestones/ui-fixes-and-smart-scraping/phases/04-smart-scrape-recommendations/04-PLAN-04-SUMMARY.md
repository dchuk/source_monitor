---
phase: "04"
plan: "04"
title: "Test-First Scrape Comparison Page"
status: complete
---

## What Was Built

Test-first scrape feature: picks a recent item from a source, scrapes it on-demand via ItemScraper, and shows a comparison page with feed vs scraped word count. Button on source show page triggers the test, result replaces via Turbo Stream.

## Commits

| Hash | Message |
|------|---------|
| 325bf76 | feat(scrape-test): add ScrapeTestsController with route and result view |
| 7f34b2c | feat(scrape-test): add Test Scrape button to source show page |

## Tasks Completed

1. **Create ScrapeTestsController** -- Controller with create action, picks test item, scrapes it, computes improvement percentage.
2. **Add route for scrape tests** -- `resource :scrape_test, only: :create` nested under sources.
3. **Create scrape test result partial** -- Grid comparison view with feed vs scraped word counts and improvement indicator.
4. **Add Test Scrape button to source show page** -- Button visible when scraping disabled, triggers POST via Turbo.

## Files Modified

- `app/controllers/source_monitor/source_scrape_tests_controller.rb` (new)
- `config/routes.rb`
- `app/views/source_monitor/source_scrape_tests/_result.html.erb` (new)
- `app/views/source_monitor/source_scrape_tests/show.html.erb` (new)
- `app/views/source_monitor/sources/_details.html.erb`
- `test/controllers/source_monitor/source_scrape_tests_controller_test.rb` (new)

## Deviations

- Tasks 1-3 were committed together since the controller, route, and view are interdependent.
