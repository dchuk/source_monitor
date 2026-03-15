---
phase: "01"
plan: "01"
title: "Security & Controller Fixes"
wave: 1
depends_on: []
must_haves:
  - "ImportHistoryDismissalsController verifies user ownership before dismissing"
  - "DashboardController replaces .permit! with explicit parameter allowlist"
  - "SourceTurboResponses uses ActionController::Base.helpers.pluralize instead of view_context.pluralize"
  - "BulkScrapeEnablementsController reads default adapter from DB column default instead of hardcoded string"
---

## Tasks

### Task 1: Add user ownership check to ImportHistoryDismissalsController (C6 — Security)
**Files:** `app/controllers/source_monitor/import_history_dismissals_controller.rb`, `test/controllers/source_monitor/import_history_dismissals_controller_test.rb`
**Action:** Scope the `ImportHistory.find` to only records belonging to the current user. Change:
```ruby
import_history = ImportHistory.find(params[:import_history_id])
```
to:
```ruby
import_history = ImportHistory.where(user_id: source_monitor_current_user&.id).find(params[:import_history_id])
```
This ensures a user cannot dismiss another user's import history. If no user is signed in, the query returns no results and raises `ActiveRecord::RecordNotFound` (handled by Rails default 404).

**Tests:** Add test that verifies a user cannot dismiss an import history belonging to a different user (expect `ActiveRecord::RecordNotFound`). Add test that the happy path still works for the owning user.
**Acceptance:** Dismissing another user's import history raises RecordNotFound. Existing tests pass.

### Task 2: Replace `.permit!` with explicit allowlist in DashboardController (C9 — Security)
**Files:** `app/controllers/source_monitor/dashboard_controller.rb`, `test/controllers/source_monitor/dashboard_controller_test.rb`
**Action:** Replace the `schedule_pages_params` method:
```ruby
def schedule_pages_params
  params.fetch(:schedule_pages, {}).permit!.to_h
end
```
with an explicit allowlist of the keys that `upcoming_fetch_schedule` actually uses. Check what keys `schedule_pages` accepts — these are pagination page numbers for the schedule groups (e.g., `page_1`, `page_2`, etc.). The pattern is dynamic string keys with integer values. Use:
```ruby
def schedule_pages_params
  raw = params.fetch(:schedule_pages, {})
  return {} unless raw.respond_to?(:permit)

  permitted_keys = raw.keys.select { |k| k.to_s.match?(/\Apage_\d+\z/) }
  raw.permit(*permitted_keys).to_h
end
```
This allowlists only `page_N` keys, preventing injection of arbitrary parameters.

**Tests:** Add test that `schedule_pages` with valid `page_1` key works. Add test that non-page keys are filtered out.
**Acceptance:** Dashboard index renders with pagination params. Non-page keys are stripped. No `.permit!` calls remain.

### Task 3: Replace `view_context.pluralize` with helper reference in SourceTurboResponses (C7)
**Files:** `app/controllers/source_monitor/source_turbo_responses.rb`
**Action:** In `bulk_scrape_flash_payload`, change:
```ruby
pluralizer = ->(count, word) { view_context.pluralize(count, word) }
```
to:
```ruby
pluralizer = ->(count, word) { ActionController::Base.helpers.pluralize(count, word) }
```
This decouples the pluralizer from the view context, making it testable in isolation and avoiding potential issues when view_context is not fully initialized.

**Tests:** Existing bulk scrape controller tests should continue to pass. No new tests needed — this is a safe refactor of an implementation detail.
**Acceptance:** Bulk scrape responses still render correct pluralized messages. All existing tests pass.

### Task 4: Replace hardcoded "readability" adapter in BulkScrapeEnablementsController (C11)
**Files:** `app/controllers/source_monitor/bulk_scrape_enablements_controller.rb`
**Action:** The `default_adapter` method currently returns a hardcoded `"readability"`. The DB column `scraper_adapter` has a default of `"readability"` defined in the migration. Replace:
```ruby
def default_adapter
  "readability"
end
```
with:
```ruby
def default_adapter
  Source.column_defaults["scraper_adapter"] || "readability"
end
```
This reads the default from the DB schema, so if the column default ever changes in a migration, the controller stays in sync. The `|| "readability"` is a safety fallback.

**Tests:** Add test that `default_adapter` returns the column default. Existing bulk scrape enablement tests should pass.
**Acceptance:** Bulk scrape enablement uses the DB column default. Hardcoded `"readability"` removed from controller logic (kept only as fallback).
