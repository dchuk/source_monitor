---
phase: "01"
plan: "01"
title: "Dismissible OPML Import Banner"
status: complete
started_at: "2026-03-05"
completed_at: "2026-03-05"
---

## What Was Built
Dismissible OPML import banner on the sources index page. Users can now click an X button to dismiss the import history notification. Dismissed banners are hidden via a `dismissed_at` timestamp on the ImportHistory model, filtered out of the controller query, and removed from the DOM via Turbo Stream.

## Tasks Completed
- Task 1: Add dismissed_at migration (commit: a8eca76)
- Task 2: Create import history dismissal endpoint (commit: 04ff496)
- Task 3: Update banner partial with dismiss button (commit: 4b176e8)
- Task 4: Filter dismissed imports from controller query (commit: 73d7e84)

## Files Modified
- `db/migrate/20260305120000_add_dismissed_at_to_import_histories.rb` (created)
- `test/dummy/db/schema.rb` (modified - schema dump)
- `app/controllers/source_monitor/import_history_dismissals_controller.rb` (created)
- `config/routes.rb` (modified - added nested dismissal resource)
- `test/controllers/source_monitor/import_history_dismissals_controller_test.rb` (created)
- `app/views/source_monitor/sources/_import_history_panel.html.erb` (modified - added dismiss button)
- `app/models/source_monitor/import_history.rb` (modified - added not_dismissed scope)
- `app/controllers/source_monitor/sources_controller.rb` (modified - chained not_dismissed)
- `test/models/source_monitor/import_history_dismissed_test.rb` (created)

## Deviations
- Used `resource :dismissal` (singular nested resource with POST) instead of `PATCH /import_histories/:id/dismiss` to follow the project's Everything-is-CRUD routing convention
- 404 test uses `assert_response :not_found` instead of `assert_raises(ActiveRecord::RecordNotFound)` because Rails integration tests convert exceptions to HTTP responses

## Test Results
- 1228 runs, 3809 assertions, 0 failures, 0 errors, 0 skips
- RuboCop: 0 offenses on all changed files
