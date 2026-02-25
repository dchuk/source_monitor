---
phase: 4
plan: 1
title: UI Quick Fixes
status: complete
completed: 2026-02-22
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 3dc5953
deviations: []
---

Three targeted CSS/HTML fixes resolving a spurious navigation warning, toast overlap with the nav header, and misaligned columns across grouped fetch schedule tables.

## What Was Built

- Import wizard submit form now disables the confirm-navigation Stimulus controller on submit, preventing a spurious beforeunload/turbo:before-visit dialog after the import completes
- Toast notification container repositioned from `top-4` to `top-16` so toasts render below the 64px nav header
- Dashboard fetch schedule tables use `table-fixed` layout with explicit percentage column widths (45/15/22/18%) so each time-bracket group's columns align consistently

## Files Modified

- `app/views/source_monitor/import_sessions/steps/_confirm.html.erb` -- added `data: { action: "submit->confirm-navigation#disable" }` to the confirm-step form_with
- `app/views/layouts/source_monitor/application.html.erb` -- changed `top-4` to `top-16` on toast container div
- `app/views/source_monitor/dashboard/_fetch_schedule.html.erb` -- added `table-fixed` class to table; added explicit `w-[45%]`, `w-[15%]`, `w-[22%]`, `w-[18%]` widths to column headers
