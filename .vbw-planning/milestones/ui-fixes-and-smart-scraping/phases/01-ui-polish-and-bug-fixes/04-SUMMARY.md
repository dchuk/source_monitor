---
phase: "01"
plan: "04"
title: "Sortable Computed Columns on Sources Index"
status: complete
started_at: "2026-03-05"
completed_at: "2026-03-05"
---

## What Was Built
Added Ransack-based sorting for the three computed columns (New Items/Day, Avg Feed Words, Avg Scraped Words) on the Sources index page. Each column uses a ransacker with a PostgreSQL subquery for aggregate computation, matching the existing sort pattern with arrows, aria-sort attributes, and Turbo Frame targeting.

## Tasks Completed
- Task 1: Add ransackers to Source model (commit: 7d8679d)
- Task 2: Update sources index view for sortable headers (commit: e4065e2)
- Task 3: Test sortable columns (commit: a4265d2)

## Files Modified
- `app/models/source_monitor/source.rb` — added 3 ransacker definitions and updated ransackable_attributes
- `app/views/source_monitor/sources/index.html.erb` — replaced 3 plain `<th>` headers with sortable `table_sort_link` pattern
- `test/controllers/source_monitor/sources_controller_sort_test.rb` — new file with 9 integration tests

## Deviations
- None

## Test Results
- 9 new sort tests: all passing (0 failures, 0 errors)
- Full suite: 1231 runs, 3792 assertions, 0 failures, 8 errors (all pre-existing in favicon/image download tests, unrelated to this plan)
- RuboCop: 0 offenses
