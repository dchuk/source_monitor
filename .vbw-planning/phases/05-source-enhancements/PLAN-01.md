---
phase: 5
plan: 1
title: Sources Pagination & Column Filtering
wave: 1
depends_on: []
must_haves:
  - "sources index returns paginated results (25/page default) with per_page URL param capped at 100"
  - "prev/next pagination controls rendered below sources table matching items index pattern"
  - "Ransack dropdown filters for status, health_status, feed_format, scraper_adapter present in sources index"
  - "text search field searches name + feed_url + website_url via Ransack q[] params"
  - "filter state preserved across pagination (q[] params passed through page links)"
  - "Source.ransackable_attributes includes status, health_status, feed_format, scraper_adapter for dropdown filters"
  - "all existing sources controller tests pass, new tests cover pagination and filter behavior"
  - "RuboCop zero offenses"
skills_used: []
---

## Objective

Add pagination and full column filtering to the sources index page. Pagination uses the existing `SourceMonitor::Pagination::Paginator` class (same as ItemsController). Column filtering adds dropdown filters for status, health_status, feed_format, and scraper_adapter alongside the existing text search.

## Context

- `@` `app/controllers/source_monitor/sources_controller.rb` -- current index action returns `@q.result` unpaginated
- `@` `app/controllers/source_monitor/items_controller.rb` -- reference pagination pattern (PER_PAGE=25, Paginator usage, view variables)
- `@` `app/views/source_monitor/sources/index.html.erb` -- current view with table, no pagination controls, single text search
- `@` `app/views/source_monitor/items/index.html.erb` -- reference pagination controls layout (prev/next at bottom of table)
- `@` `lib/source_monitor/pagination/paginator.rb` -- existing Paginator class with normalize_per_page capping at 100
- `@` `app/controllers/concerns/source_monitor/sanitizes_search_params.rb` -- search param sanitization concern
- `@` `app/models/source_monitor/source.rb` -- current ransackable_attributes (name, feed_url, website_url, created_at, fetch_interval_minutes, items_count, last_fetched_at)
- `@` `test/controllers/source_monitor/sources_controller_test.rb` -- existing controller tests

## Tasks

### Task 1: Add pagination to SourcesController#index

**Files:** `app/controllers/source_monitor/sources_controller.rb`

Add `PER_PAGE = 25` constant. In `#index`, wrap `@q.result` with `Paginator.new(scope:, page: params[:page], per_page: params[:per_page] || PER_PAGE).paginate`. Expose `@sources` (from paginator.records), `@page`, `@has_next_page`, `@has_previous_page` as instance variables. Pass `paginator.records` (not full result) to SourcesIndexMetrics `result_scope:`. Update `_row` collection render to use `@sources`.

### Task 2: Add pagination controls to sources index view

**Files:** `app/views/source_monitor/sources/index.html.erb`

Add pagination footer below the `</table>` tag inside the turbo_frame, matching the items index pattern exactly: `Page N` text + prev/next links with disabled states. Preserve `q[]` search params and `per_page` in pagination link URLs. Prev/next links use `data: { turbo_frame: "source_monitor_sources_table" }` for Turbo Frame updates.

### Task 3: Add dropdown filter controls for status columns

**Files:** `app/views/source_monitor/sources/index.html.erb`, `app/models/source_monitor/source.rb`

Add dropdown `<select>` filters for `status_eq` (active/paused), `health_status_eq` (healthy/warning/declining/critical), `feed_format_eq` (rss/atom/json), and `scraper_adapter_eq` within the search form. Each dropdown submits via the existing search form. Add `status`, `health_status`, `feed_format`, `scraper_adapter` to `Source.ransackable_attributes`. Add an "active filter" banner (matching the existing search_term banner pattern) showing applied filters with clear links. Note: `active` is a boolean column -- use `active_eq` Ransack predicate; map "active" -> true, "paused" -> false in the view label.

### Task 4: Write pagination and filter tests

**Files:** `test/controllers/source_monitor/sources_controller_test.rb`

Add tests: (1) index returns paginated results (create 30 sources, assert 25 returned on page 1, remainder on page 2), (2) per_page param respected (per_page=10 returns 10), (3) per_page capped at 100, (4) page param works (page=2 returns remaining sources), (5) filter by health_status_eq returns only matching sources, (6) filter by scraper_adapter_eq works, (7) combined text search + dropdown filter returns intersection, (8) pagination preserves filter params across pages.

### Task 5: Verify full integration and cleanup

**Files:** all files from tasks 1-4

Run `bin/rubocop` on all changed files. Run `bin/rails test test/controllers/source_monitor/sources_controller_test.rb`. Verify no regressions. Ensure filter dropdowns render correctly with no selected value by default. Verify `per_page` normalization handles edge cases (negative, zero, string).

## Verification

```bash
bin/rails test test/controllers/source_monitor/sources_controller_test.rb
bin/rubocop app/controllers/source_monitor/sources_controller.rb app/views/source_monitor/sources/index.html.erb app/models/source_monitor/source.rb
```

## Success Criteria

- Sources index shows 25 sources per page by default
- `?per_page=10` reduces to 10 per page; `?per_page=200` caps at 100
- Prev/next controls appear at bottom of table, disabled when at boundary
- Dropdown filters for health_status, feed_format, scraper_adapter functional via Ransack
- Active/Paused filter works on the boolean `active` column
- Text search + dropdown filters composable
- All tests pass, RuboCop zero offenses
