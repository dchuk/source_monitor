---
phase: 4
plan: 3
title: Published Column Fix
status: complete
completed: 2026-02-22
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 4b3c79e
deviations:
  - "Parser works correctly; root cause is feeds genuinely lacking dates. Fix is display-only fallback."
---

Replaced "Unpublished" label with created_at fallback display when published_at is nil. Investigation confirmed the EntryParser correctly extracts timestamps — the issue is feeds that genuinely lack date fields.

## What Was Built

- Items index, item details, and source details views now show `created_at` in muted style when `published_at` is nil instead of "Unpublished"
- Added 4 controller tests covering published_at rendering and created_at fallback for both index and show actions
- Added 2 unit tests for EntryParser confirming timestamp extraction works for feeds with and without dates

## Files Modified

- `app/views/source_monitor/items/index.html.erb` -- replaced "Unpublished" with created_at fallback in muted span
- `app/views/source_monitor/items/_details.html.erb` -- same fallback pattern in item detail and details hash
- `app/views/source_monitor/sources/_details.html.erb` -- same fallback pattern in source detail items table
- `test/controllers/source_monitor/items_controller_test.rb` -- added 4 new published_at/created_at tests
- `test/lib/source_monitor/items/item_creator_test.rb` -- added 2 EntryParser timestamp tests
