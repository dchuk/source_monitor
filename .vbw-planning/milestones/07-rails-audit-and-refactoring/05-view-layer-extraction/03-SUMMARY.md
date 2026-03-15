---
phase: "05"
plan: "03"
title: "Dropdown Stabilization & JavaScript Cleanup"
status: complete
commits: ["491fae1"]
tasks_completed: 5
tasks_total: 5
deviations: []
---

## What Was Built

Simplified the dropdown Stimulus controller from 109 lines of fragile async stimulus-use loading to 30 lines of pure CSS class toggling. Removed all window namespace pollution (`window.SourceMonitorControllers`, `window.SourceMonitorStimulus`). Added unique `data-testid` attributes to dropdown containers for test isolation. Click-outside dismissal now uses a document-level listener managed in `connect()`/`disconnect()` for proper cleanup during Turbo Drive navigation.

## Commits

- `491fae1` refactor(05-03): simplify dropdown controller and remove JS globals

## Tasks Completed

1. Simplified dropdown_controller.js to CSS class toggle only (109 -> 30 lines)
2. Removed `window.SourceMonitorControllers` from notification_controller.js
3. Removed `window.SourceMonitorStimulus` from application.js
4. Updated dropdown HTML with unique data-testid and removed declarative click@window
5. Verified: yarn build clean, 1491 tests pass, no remaining global/stimulus-use references

## Files Modified

- `app/assets/javascripts/source_monitor/controllers/dropdown_controller.js` -- rewritten to pure CSS toggle
- `app/assets/javascripts/source_monitor/controllers/notification_controller.js` -- removed global registration
- `app/assets/javascripts/source_monitor/application.js` -- removed window.SourceMonitorStimulus
- `app/views/source_monitor/sources/_row.html.erb` -- added data-testid, removed click@window
- `app/views/source_monitor/sources/_health_status_badge.html.erb` -- added unique data-testid per source, removed click@window
- `app/assets/builds/source_monitor/application.js` -- rebuilt
- `app/assets/builds/source_monitor/application.js.map` -- rebuilt

## Deviations

None.
