---
phase: "01"
plan: "01"
title: "Security & Controller Fixes"
status: complete
---

## What Was Built
Two security fixes (user ownership scoping, parameter allowlisting) and two controller refactors (decoupled pluralizer, dynamic DB column default) across 4 controllers with full test coverage.

## Commits
- af94023 fix(security): scope ImportHistoryDismissalsController to current user
- 9501b2f fix(security): replace .permit! with explicit allowlist in DashboardController
- 0fb3e82 refactor(controllers): use ActionController::Base.helpers.pluralize in SourceTurboResponses
- 4ea2acd refactor(controllers): read default scraper adapter from DB column default

## Tasks Completed
- Task 1: Scoped ImportHistoryDismissalsController to current user ownership, preventing cross-user dismissals
- Task 2: Replaced .permit! with pattern-based allowlist accepting only page_N keys in DashboardController
- Task 3: Replaced view_context.pluralize with ActionController::Base.helpers.pluralize in SourceTurboResponses
- Task 4: Replaced hardcoded "readability" with Source.column_defaults["scraper_adapter"] in BulkScrapeEnablementsController

## Files Modified
- app/controllers/source_monitor/import_history_dismissals_controller.rb
- app/controllers/source_monitor/dashboard_controller.rb
- app/controllers/source_monitor/source_turbo_responses.rb
- app/controllers/source_monitor/bulk_scrape_enablements_controller.rb
- test/controllers/source_monitor/import_history_dismissals_controller_test.rb
- test/controllers/source_monitor/dashboard_controller_test.rb
- test/controllers/source_monitor/bulk_scrape_enablements_controller_test.rb

## Deviations
- Task 1: Existing tests had no auth configured (source_monitor_current_user was nil), so tests were updated to use configure_authentication pattern from import_sessions_controller_test.rb. Added teardown with reset_configuration! to avoid test pollution.
