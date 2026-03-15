---
phase: "01"
plan: "03"
title: "View & Helper Extraction"
status: complete
---

## What Was Built
Extracted duplicated view logic into shared helpers and removed dead code. Replaced inline scrape status badge rendering with the existing helper, consolidated 4 compact_blank fallback patterns into a single shared method, and removed an unreachable JS error delay override while documenting the Ruby toast constants as the single source of truth.

## Commits
- 8b0a35d refactor: replace inline scrape status badge with helper call in items index
- d3548f5 refactor(helpers): extract compact_blank fallback to shared helper
- 15e7d53 refactor(toast): remove dead JS error delay override and document constants

## Tasks Completed
- Task 1: Replaced inline scrape status case/when badge logic in items/index.html.erb with existing item_scrape_status_badge helper call
- Task 2: Extracted compact_blank fallback pattern to compact_blank_hash shared helper; replaced 4 inline occurrences (3 views, 1 helper) with helper calls; added 3 tests
- Task 3: Removed dead JS error delay override in notification_controller.js (condition never triggers since Ruby sends 6000ms); documented Ruby toast constants as single source of truth; rebuilt JS assets

## Files Modified
- app/views/source_monitor/items/index.html.erb
- app/helpers/source_monitor/application_helper.rb
- app/views/source_monitor/sources/index.html.erb
- app/views/source_monitor/sources/_row.html.erb
- test/helpers/source_monitor/application_helper_test.rb
- app/assets/javascripts/source_monitor/controllers/notification_controller.js
- app/controllers/source_monitor/application_controller.rb
- app/assets/builds/source_monitor/application.js
- app/assets/builds/source_monitor/application.js.map

## Deviations
- None
