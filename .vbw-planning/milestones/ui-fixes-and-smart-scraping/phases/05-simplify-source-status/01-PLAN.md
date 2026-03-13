---
phase: "05"
plan: "01"
title: "Data Migration and Source Model Updates"
wave: 1
depends_on: []
must_haves:
  - "Migration to rename health_status values: healthy->working, warning->failing, critical->failing, auto_paused->working, unknown->working"
  - "Source model default health_status changed from 'healthy' to 'working'"
  - "Source model scopes updated if any reference old status values"
---

# Plan 01: Data Migration and Source Model Updates

## Goal
Create the database migration to rename the 7 health statuses down to 4, and update the Source model's default attribute value.

## Tasks

### Task 1: Create data migration for health_status column values
**Files:** `db/migrate/YYYYMMDD120000_simplify_health_status_values.rb`

Create a reversible migration that:
- `UPDATE sourcemon_sources SET health_status = 'working' WHERE health_status IN ('healthy', 'auto_paused', 'unknown')`
- `UPDATE sourcemon_sources SET health_status = 'failing' WHERE health_status IN ('warning', 'critical')`
- `declining` and `improving` remain unchanged
- For `down`: reverse `working` -> `healthy`, `failing` -> `critical` (best-effort reverse)

Use a timestamp like `20260311120000`.

### Task 2: Update Source model default health_status
**Files:** `app/models/source_monitor/source.rb`

- Change `attribute :health_status, :string, default: "healthy"` to `attribute :health_status, :string, default: "working"`
- Update the `apply_status` fallback on line 147: change `"healthy"` to `"working"` in `source.health_status.presence || "healthy"` -- NOTE: this is in `source_health_monitor.rb`, not in source.rb. Only change the model file here.

### Task 3: Run migration on dummy app database
**Files:** (none -- shell command)

Run `cd test/dummy && bin/rails db:migrate` to apply the migration to the test database.
