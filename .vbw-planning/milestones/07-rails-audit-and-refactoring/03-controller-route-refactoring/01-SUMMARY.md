---
phase: "03"
plan: "01"
title: "Extract ItemScrapesController & Simplify Logging"
status: complete
---

## What Was Built
Extracted custom scrape action from ItemsController into dedicated ItemScrapesController following everything-is-CRUD convention. Simplified logging by removing defensive `defined?(Rails)` checks.

## Commits
- 1884883 refactor(controllers): extract ItemScrapesController from Items#scrape

## Tasks Completed
1. Created ItemScrapesController with create action at POST /items/:item_id/scrape
2. Updated routes from `post :scrape, on: :member` to `resource :scrape, only: :create, controller: "item_scrapes"`
3. Removed scrape action, scrape_flash_payload, and log_manual_scrape from ItemsController
4. Updated view references from scrape_item_path to item_scrape_path
5. Added 4 controller tests (turbo_stream success, html redirect, enqueue failure, already enqueued)

## Files Modified
- app/controllers/source_monitor/item_scrapes_controller.rb (new)
- test/controllers/source_monitor/item_scrapes_controller_test.rb (new)
- app/controllers/source_monitor/items_controller.rb
- app/views/source_monitor/items/_details.html.erb
- config/routes.rb

## Deviations
None.
