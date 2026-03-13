---
phase: "01"
plan: "01"
title: "Dismissible OPML Import Banner"
wave: 1
depends_on: []
must_haves:
  - "Add dismissed_at column to import_histories"
  - "Dismiss endpoint that sets dismissed_at via Turbo Stream"
  - "Filter dismissed imports from sources index query"
  - "Dismiss button in banner partial"
---

## Tasks

### Task 1: Add dismissed_at migration

Create migration to add `dismissed_at` (datetime, nullable) to the import_histories table.

**Files:**
- Create: `db/migrate/TIMESTAMP_add_dismissed_at_to_import_histories.rb`

**Acceptance:**
- Migration adds `dismissed_at` column (datetime, null: true)
- Migration is reversible

### Task 2: Create import history dismissal endpoint

Add a route and controller action to dismiss an import history record. Use RESTful pattern: `PATCH /import_histories/:id/dismiss` or a nested resource.

**Files:**
- Modify: `config/routes.rb` — add route for dismissal
- Create: `app/controllers/source_monitor/import_history_dismissals_controller.rb` — PATCH action sets `dismissed_at` and responds with Turbo Stream
- Create: `test/controllers/source_monitor/import_history_dismissals_controller_test.rb`

**Details:**
- Controller finds ImportHistory by ID, sets `dismissed_at = Time.current`, saves
- Responds with `turbo_stream.remove("source_monitor_import_history_panel")`
- Returns 404 if not found
- HTML fallback redirects back to sources index

### Task 3: Update banner partial with dismiss button

Add a dismiss/close button to the import history panel that triggers the dismissal endpoint via Turbo Stream.

**Files:**
- Modify: `app/views/source_monitor/sources/_import_history_panel.html.erb`

**Details:**
- Add an "x" or "Dismiss" button in the banner header area
- Button submits via `button_to` with `method: :patch` targeting the dismissal endpoint
- Include `data: { turbo_stream: true }` for inline removal

### Task 4: Filter dismissed imports from controller query

Update the sources controller to exclude dismissed import histories from the query.

**Files:**
- Modify: `app/models/source_monitor/import_history.rb` — add `not_dismissed` scope
- Modify: `app/controllers/source_monitor/sources_controller.rb:45` — chain `.not_dismissed` or `.where(dismissed_at: nil)`
- Create: `test/models/source_monitor/import_history_dismissed_test.rb`

**Acceptance:**
- Dismissed imports no longer show in the banner
- New imports (dismissed_at: nil) still show
- Tests verify scope filtering
