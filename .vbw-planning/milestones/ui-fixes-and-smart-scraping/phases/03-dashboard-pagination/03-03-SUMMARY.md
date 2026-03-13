---
phase: "03"
plan: "03"
title: "Sources Index Pagination UX Upgrade"
status: complete
---

# Plan 03 Summary: Sources Index Pagination UX Upgrade

## What Was Built

Replaced the manual prev/next pagination on the sources index with the shared pagination partial from Plan 01. The sources controller now exposes the full paginator result with total_count/total_pages, enabling page numbers and jump-to-page navigation.

## Tasks Completed

1. **Update SourcesController to expose @paginator** -- Assigned `@paginator = paginate(...)` result, kept `@sources = @paginator.records` for backward compat. Removed `@page`, `@has_next_page`, `@has_previous_page`.
2. **Replace sources index pagination with shared partial** -- Removed ~25 lines of manual pagination markup, replaced with single `render "source_monitor/shared/pagination"` call preserving search params and Turbo Frame targeting.
3. **Update sources controller tests** -- Added tests for page numbers rendering, jump-to-page with search params preservation.
4. **Clean up unused pagination code** -- Verified no leftover references to removed instance variables.

## Files Modified

- `app/controllers/source_monitor/sources_controller.rb` -- Exposed `@paginator`, removed individual pagination ivars
- `app/views/source_monitor/sources/index.html.erb` -- Replaced manual pagination with shared partial
- `test/controllers/source_monitor/sources_controller_test.rb` -- Added pagination UX tests

## Commits

- `71b0d37` refactor(sources): expose @paginator result in SourcesController index
- `9f151e3` feat(sources): replace manual pagination with shared partial
- `7d4086b` test(sources): add pagination UX tests for page numbers and jump-to-page

## Deviations

None.

## Test Results

All sources controller tests pass, 0 failures.
