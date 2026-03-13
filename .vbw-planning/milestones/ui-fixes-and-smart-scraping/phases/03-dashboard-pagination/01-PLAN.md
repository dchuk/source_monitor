---
phase: "03"
plan: "01"
title: "Paginator Enhancement + Shared Pagination Partial"
wave: 1
depends_on: []
must_haves:
  - "Paginator supports total_count and total_pages"
  - "Shared pagination partial with page numbers, jump-to-page, prev/next"
  - "All existing paginator tests still pass"
  - "New unit tests for total_count/total_pages behavior"
---

# Plan 01: Paginator Enhancement + Shared Pagination Partial

## Goal

Extend `SourceMonitor::Pagination::Paginator` with `total_count` and `total_pages` fields, then extract a reusable pagination partial that renders page numbers, jump-to-page form, and prev/next navigation.

## Task 1: Add total_count and total_pages to Paginator

**What:** Extend `Pagination::Result` struct with `total_count` and `total_pages` fields. Modify `Paginator#paginate` to compute these values. For ActiveRecord::Relation scopes, use `.count` (single DB query). For Array scopes, use `.size`.

**Files to modify:**
- `lib/source_monitor/pagination/paginator.rb`

**Implementation details:**
- Add `total_count` and `total_pages` to the `Result` struct keyword_init
- Add `total_pages` method to Result: `(total_count.to_f / per_page).ceil`
- In `Paginator#paginate`, compute `total_count` before fetching records:
  - For AR::Relation: `scope.count` (does `SELECT COUNT(*)`)
  - For Array: `Array(scope).size`
- Pass `total_count` into Result. `total_pages` is derived.
- The `total_count` query happens once, separate from the offset/limit fetch
- Add a `total_pages` convenience method on Result that computes `[1, (total_count.to_f / per_page).ceil].max`

**Acceptance criteria:**
- `result.total_count` returns the total number of records in the scope
- `result.total_pages` returns `ceil(total_count / per_page)`, minimum 1
- Backward compatible: existing code using `has_next_page?`, `has_previous_page?`, `next_page`, `previous_page` still works unchanged

## Task 2: Write unit tests for total_count and total_pages

**What:** Add tests to the existing paginator test file covering the new fields.

**Files to modify:**
- `test/lib/source_monitor/pagination/paginator_test.rb`

**Test cases:**
- `test "provides total_count and total_pages for relation scope"` -- 6 items, per_page 3 -> total_count 6, total_pages 2
- `test "provides total_count and total_pages for array scope"` -- Array of 10 items, per_page 4 -> total_count 10, total_pages 3
- `test "total_pages is at least 1 for empty scope"` -- Empty scope -> total_count 0, total_pages 1
- `test "total_count does not affect existing pagination behavior"` -- Verify has_next_page/has_previous_page still correct alongside total_count

**Acceptance criteria:**
- All new tests pass
- All existing paginator tests still pass

## Task 3: Create shared pagination partial

**What:** Create a reusable pagination partial at `app/views/source_monitor/shared/_pagination.html.erb` that renders:
1. "Page X of Y" text on the left
2. Page number links (with window around current page, ellipsis for gaps)
3. Jump-to-page mini form
4. Previous/Next buttons

The partial accepts these locals:
- `paginator_result` -- a `Pagination::Result` with total_count/total_pages
- `base_path` -- the URL path to link to (e.g., `source_monitor.sources_path`)
- `extra_params` -- hash of additional query params to preserve (search, filters, per_page)
- `turbo_frame` -- optional Turbo Frame target for the links (defaults to nil)

**Files to create:**
- `app/views/source_monitor/shared/_pagination.html.erb`

**Implementation details:**
- Page numbers: show first page, last page, current page +/- 2, with "..." ellipsis gaps
- Jump-to-page: small `<form>` with a number input and "Go" button, GET to base_path with page param
- Previous/Next: disabled state when on first/last page
- All links preserve `extra_params` (search filters, per_page, sort)
- If `turbo_frame` is provided, add `data-turbo-frame` to all links and form
- Tailwind styling consistent with existing pagination in sources index
- When total_pages is 1, render minimal "Page 1 of 1" without nav controls

**Acceptance criteria:**
- Partial renders correctly with various total_pages values (1, 2, 5, 10, 50)
- All links preserve extra_params
- Turbo Frame targeting works when specified
- Disabled states for first/last page prev/next buttons

## Task 4: Create pagination partial helper

**What:** Add a helper method to `ApplicationHelper` that builds the page number windows (which page numbers to show, where to put ellipses) so the partial stays clean.

**Files to modify:**
- `app/helpers/source_monitor/application_helper.rb`

**Implementation details:**
- Add `pagination_page_numbers(current_page:, total_pages:, window: 2)` method
- Returns an array of page numbers and `:gap` symbols, e.g., `[1, :gap, 4, 5, 6, 7, 8, :gap, 20]`
- Algorithm: always include page 1 and last page; include current_page +/- window; fill gaps with `:gap`
- Used by the shared pagination partial to render page links

**Acceptance criteria:**
- `pagination_page_numbers(current_page: 1, total_pages: 5)` -> `[1, 2, 3, 4, 5]` (no gaps when small)
- `pagination_page_numbers(current_page: 5, total_pages: 10)` -> `[1, :gap, 3, 4, 5, 6, 7, :gap, 10]`
- `pagination_page_numbers(current_page: 1, total_pages: 1)` -> `[1]`
- `pagination_page_numbers(current_page: 1, total_pages: 20)` -> `[1, 2, 3, :gap, 20]`

## Task 5: Write tests for pagination helper

**What:** Unit tests for the `pagination_page_numbers` helper method.

**Files to create:**
- `test/helpers/source_monitor/pagination_helper_test.rb`

**Test cases:**
- Small range (total_pages <= 2*window+3): all pages, no gaps
- Large range with current at start: pages near start + gap + last
- Large range with current at end: first + gap + pages near end
- Large range with current in middle: first + gap + window + gap + last
- Edge case: single page -> `[1]`

**Acceptance criteria:**
- All helper tests pass
- Helper produces correct page number arrays for all edge cases

## File Disjointness (Wave 1)

This plan modifies:
- `lib/source_monitor/pagination/paginator.rb` (paginator lib)
- `test/lib/source_monitor/pagination/paginator_test.rb` (paginator tests)
- `app/views/source_monitor/shared/_pagination.html.erb` (NEW partial)
- `app/helpers/source_monitor/application_helper.rb` (helper addition)
- `test/helpers/source_monitor/pagination_helper_test.rb` (NEW test)

No overlap with Plan 02 (dashboard schedule files) or Plan 04 (stats query files).
