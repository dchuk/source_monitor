---
phase: "04"
plan: "05"
title: "Bulk Scrape Enablement with Confirmation Modal"
status: complete
---

## What Was Built

Bulk scrape enablement flow: users can select multiple scrape candidate sources via checkboxes, see a sticky action bar with selected count, open a confirmation modal, and bulk-enable scraping for all selected sources in one action.

## Commits

- `391e957` feat: add BulkScrapeEnablementsController with route and tests
- `b0d1995` feat(views): add bulk scrape checkboxes, action bar, and confirmation modal
- `ef4a71d` feat(js): extend select-all controller with action bar and count targets

## Tasks Completed

1. **BulkScrapeEnablementsController** - Created controller with `create` action that bulk-updates `scraping_enabled` and `scraper_adapter` on selected sources. Responds with Turbo Stream (toast + redirect) and HTML formats. Handles empty selection with warning.
2. **Route** - Added `resources :bulk_scrape_enablements, only: :create` as top-level route in engine.
3. **Checkboxes and bulk action bar** - Wrapped sources table in form with `select-all` Stimulus controller. Added header checkbox (master toggle) and row checkboxes for scrape candidate sources only. Added sticky bottom action bar showing selected count and "Enable Scraping" button.
4. **Confirmation modal** - Created `_bulk_scrape_enable_modal.html.erb` partial using existing `modal` Stimulus controller. Shows warning text and "Confirm Enable" submit button wired into the bulk form.
5. **Select-all controller extension** - Added `actionBar` and `count` targets. New `updateActionBar()` method shows/hides action bar and updates count on every checkbox toggle.

## Files Modified

- `app/controllers/source_monitor/bulk_scrape_enablements_controller.rb` (new)
- `config/routes.rb`
- `app/views/source_monitor/sources/index.html.erb`
- `app/views/source_monitor/sources/_row.html.erb`
- `app/views/source_monitor/sources/_bulk_scrape_enable_modal.html.erb` (new)
- `app/views/source_monitor/sources/_empty_state_row.html.erb`
- `app/assets/javascripts/source_monitor/controllers/select_all_controller.js`
- `app/assets/builds/source_monitor/application.js`
- `app/assets/builds/source_monitor/application.js.map`
- `test/controllers/source_monitor/bulk_scrape_enablements_controller_test.rb` (new)
- `test/controllers/source_monitor/sources_controller_test.rb`

## Deviations

- Plan referenced `SourceMonitor.config.scrapers.default_adapter_name` which does not exist. Used hardcoded `"readability"` string instead (matches `Sources::Params.default_attributes` convention).
- Updated `_empty_state_row.html.erb` colspan from 7 to 10 to account for the new checkbox column and correct the pre-existing count.
- Route test uses functional verification (POST + assert redirect) instead of `assert_routing` since the engine is mounted at a prefix that complicates path matching.
