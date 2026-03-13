---
phase: "03"
plan: "03"
title: "Sources Index Pagination UX Upgrade"
wave: 2
depends_on: ["01"]
must_haves:
  - "Sources index uses enhanced paginator with total_count/total_pages"
  - "Sources index uses shared pagination partial"
  - "Page numbers, jump-to-page, and prev/next all work"
  - "Search params, filters, sort, and per_page preserved across pagination"
  - "Existing sources controller tests still pass"
---

# Plan 03: Sources Index Pagination UX Upgrade

## Goal

Replace the manual prev/next pagination in the sources index with the shared pagination partial from Plan 01. Use the enhanced paginator's `total_count` and `total_pages` to show page numbers and jump-to-page.

## Task 1: Update SourcesController to expose paginator result

**What:** Modify the sources index action to pass the full paginator result to the view instead of extracting individual fields.

**Files to modify:**
- `app/controllers/source_monitor/sources_controller.rb`

**Implementation details:**
- Instead of extracting `@sources`, `@page`, `@has_next_page`, `@has_previous_page` separately, assign `@paginator = Paginator.new(...).paginate`
- Keep `@sources = @paginator.records` for backward compat with the row partial
- Remove `@page`, `@has_next_page`, `@has_previous_page` instance variables (the shared partial reads from `@paginator` directly)
- The paginator result now has `total_count` and `total_pages` from Plan 01

**Acceptance criteria:**
- `@paginator` is available in the view with all pagination fields
- `@sources` still works for the table body rendering
- No regression in existing controller behavior

## Task 2: Replace sources index pagination with shared partial

**What:** Replace the hand-rolled pagination controls at the bottom of `sources/index.html.erb` with the shared `_pagination.html.erb` partial from Plan 01.

**Files to modify:**
- `app/views/source_monitor/sources/index.html.erb`

**Implementation details:**
- Remove the existing pagination `<div>` at the bottom (lines 264-288 approximately)
- Replace with: `<%= render "source_monitor/shared/pagination", paginator_result: @paginator, base_path: source_monitor.sources_path, extra_params: pagination_extra_params, turbo_frame: "source_monitor_sources_table" %>`
- The "Page X" text on left side is now "Page X of Y" via the shared partial
- Add a private helper or view logic to build `pagination_extra_params` hash combining search params and per_page

**Implementation for extra_params building (in the view or a helper):**
```ruby
extra_params = {}
extra_params[:q] = @search_params if @search_params.present?
extra_params[:per_page] = params[:per_page] if params[:per_page].present?
```

**Acceptance criteria:**
- Page numbers render with ellipsis for large page counts
- Jump-to-page form works and preserves search/filter state
- Previous/Next buttons work as before
- Turbo Frame targeting preserves the in-page table update behavior
- All search filters, sort order, and per_page are preserved across page navigation

## Task 3: Update sources controller integration tests

**What:** Update existing controller tests to verify the new pagination UX elements.

**Files to modify:**
- Find existing sources controller test file and add pagination-specific assertions

**Test cases:**
- `test "index renders page numbers and total pages"` -- Create 30 sources, per_page 10, verify page 1 shows "Page 1 of 3" and page number links
- `test "jump to page preserves search params"` -- Search + jump to page 2, verify search params in resulting URL
- `test "pagination preserves filter params"` -- Filter by health status + paginate, verify filter preserved

**Acceptance criteria:**
- Tests verify the shared pagination partial renders correctly in context
- All existing sources tests continue to pass

## Task 4: Clean up unused pagination code

**What:** Remove any dead code left over from the old manual pagination implementation.

**Files to modify:**
- `app/views/source_monitor/sources/index.html.erb` (verify no leftover references to old `@page`, `@has_next_page`, `@has_previous_page`)
- `app/controllers/source_monitor/sources_controller.rb` (verify no leftover assigns)

**Acceptance criteria:**
- No references to removed instance variables
- `bin/rubocop` passes clean
- `bin/rails test` passes

## File Disjointness (Wave 2)

This plan modifies:
- `app/controllers/source_monitor/sources_controller.rb`
- `app/views/source_monitor/sources/index.html.erb`
- Sources controller test file(s)

Depends on Plan 01 (paginator total_count/total_pages + shared pagination partial). No conflict with Plan 02 (dashboard files) or Plan 04 (stats files).
