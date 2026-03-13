---
phase: "01"
tier: deep
result: PASS
passed: 35
failed: 0
total: 35
date: 2026-03-05
---

## Verification Results

### Tests
Full suite: **1247 runs, 3861 assertions, 0 failures, 0 errors, 0 skips** (60.78s)
New test files introduced in this phase all pass independently.

### RuboCop
**433 files inspected, no offenses detected**

### Brakeman
**0 security warnings** (1 pre-existing ignored warning, unrelated to this phase)

---

## Must-Haves Verification

### Plan 01: Dismissible OPML Import Banner
| # | Must-Have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Add dismissed_at column to import_histories | PASS | `db/migrate/20260305120000_add_dismissed_at_to_import_histories.rb` uses dynamic table prefix |
| 2 | Dismiss endpoint sets dismissed_at via Turbo Stream | PASS | `ImportHistoryDismissalsController#create` updates dismissed_at, renders turbo_stream.remove |
| 3 | Filter dismissed imports from sources index query | PASS | `sources_controller.rb:45` chains `.not_dismissed` scope |
| 4 | Dismiss button in banner partial | PASS | `_import_history_panel.html.erb` has X button via `button_to` with `data: { turbo_stream: true }` |

### Plan 02: SVG Favicon to PNG Conversion
| # | Must-Have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Detect SVG content type after favicon download | PASS | `discoverer.rb:147` checks `content_type == "image/svg+xml"` |
| 2 | Convert SVG to PNG using MiniMagick before Active Storage attach | PASS | `SvgConverter.call` uses MiniMagick::Image.read -> format("png") |
| 3 | Graceful fallback if conversion fails | PASS | `defined?(MiniMagick)` guard; `rescue StandardError` returns nil; `convert_svg_to_result` returns nil propagated as skip |
| 4 | Tests for SVG conversion path | PASS | 7 unit tests in `svg_converter_test.rb`, 3 integration tests in `discoverer_test.rb` |

### Plan 03: Recent Activity URL-First Heading
| # | Must-Have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | URL/domain leads the heading row for fetch events | PASS | `fetch_event` builds label as `"#{domain} \u2014 Fetch ##{event.id}"` |
| 2 | Format: 'domain — Fetch #N FETCH' | PASS | Uses em-dash (U+2014); tested in presenter tests |
| 3 | Existing badge and stats layout preserved | PASS | No view file changes; url_display block conditional — scrape events unchanged |
| 4 | Tests for updated presenter output | PASS | 7 tests: domain in label, nil fallback, invalid URI fallback, scrape event unchanged |

### Plan 04: Sortable Computed Columns
| # | Must-Have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | New Items/Day column sortable via Ransack | PASS | `ransacker :new_items_per_day` defined; in `ransackable_attributes`; sortable header in view |
| 2 | Avg Feed Words column sortable via Ransack | PASS | `ransacker :avg_feed_words` defined; in `ransackable_attributes`; sortable header in view |
| 3 | Avg Scraped Words column sortable via Ransack | PASS | `ransacker :avg_scraped_words` defined; in `ransackable_attributes`; sortable header in view |
| 4 | Match existing sort pattern (table_sort_link, arrows, aria) | PASS | View uses `table_sort_link`, `table_sort_arrow`, `aria-sort`, `data-sort-column`, matches existing pattern |

---

## Anti-Pattern Scan

| # | Pattern | Status | Evidence |
|---|---------|--------|----------|
| 1 | N+1 queries in dismissals controller | PASS (clean) | Controller calls `ImportHistory.find` once; no associations loaded |
| 2 | SQL injection in ransacker Arel.sql | PASS (clean) | Table names from model constants (not user input); Brakeman clean |
| 3 | XSS in new views | PASS (clean) | ERB auto-escapes; SVGs in view are server-rendered not user-controlled |
| 4 | Hardcoded table name in migration | PASS (clean) | Uses `SourceMonitor.table_name_prefix` dynamic prefix |
| 5 | Missing RecordNotFound 404 handling | PASS (clean) | Rails integration tests convert `RecordNotFound` to 404; confirmed by passing test |
| 6 | MiniMagick unavailability crash | PASS (clean) | `defined?(MiniMagick)` guard returns nil; test confirms graceful skip |
| 7 | mini_magick in gemspec (breaking for host apps) | PASS (clean) | Added to Gemfile test group only; not in gemspec |
| 8 | Ransack unrestricted attribute access | PASS (clean) | `ransackable_attributes` whitelist updated to include the 3 new columns |

---

## Convention Compliance

| # | Convention | File | Status | Detail |
|---|------------|------|--------|--------|
| 1 | frozen_string_literal comment | All new .rb files | PASS | All new files have `# frozen_string_literal: true` |
| 2 | Everything-is-CRUD routing | config/routes.rb | PASS | Used `resource :dismissal` (POST create) — deviates from original PATCH plan but matches CRUD convention |
| 3 | ActiveStorage guard `if defined?(ActiveStorage)` | N/A | PASS | No new AS usage added |
| 4 | Minitest, no RSpec/FactoryBot | All test files | PASS | All tests use `ActiveSupport::TestCase` or `ActionDispatch::IntegrationTest` |
| 5 | Configuration reset in test setup | Model test | PASS | `import_history_dismissed_test.rb` calls `reset_configuration!` |
| 6 | `create_source!` factory used | Sort test | PASS | `sources_controller_sort_test.rb` uses `create_source!` |
| 7 | Scope naming convention | import_history.rb | PASS | `scope :not_dismissed` follows existing scope naming patterns |
| 8 | Module/class autoload registration | lib/source_monitor.rb | PASS | `SvgConverter` registered via `autoload` in Favicons module |

---

## Cross-Plan Integration

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | Plans 01-04 don't conflict in routes | PASS | Routes file is clean; 4 plans use distinct controllers/resources |
| 2 | Plans 01-04 don't share modified files in conflicting ways | PASS | No overlap between plan file sets except `sources_controller.rb` and `source.rb` — both additive changes |
| 3 | Test count progression is consistent | PASS | Plan 01: 1228 runs, Plan 02: 1232 runs, Plan 04: 1231 runs, Final: 1247 runs |

---

## Pre-existing Issues

None identified. The 16 errors noted in the Plan 03 summary during its development (stalled_fetch_reconciler, solid_queue_metrics, favicon_integration etc.) do not appear in the final full suite run (0 errors). These were either environment/ordering artifacts during development or have since been resolved.

---

## Summary

Tier: deep | Result: PASS | Passed: 35/35 | Failed: none

All 4 plans in Phase 01 are fully implemented and verified:

1. **OPML Import Banner (Plan 01):** Migration, controller, route, model scope, and view are all present and correct. Tests cover turbo-stream dismiss, HTML fallback redirect, and 404 for missing records. Model tests verify scope filtering.

2. **SVG Favicon Conversion (Plan 02):** SvgConverter class cleanly handles conversion with MiniMagick, graceful nil fallback when library unavailable, proper file extension renaming. Integration into discoverer follows existing Result struct pattern. 7 unit + 3 integration tests.

3. **Recent Activity URL-First Heading (Plan 03):** Presenter restructured with domain-leading label format. Fallback to plain "Fetch #N" on nil or invalid URI. No view changes needed. 7 tests with complete coverage including edge cases.

4. **Sortable Computed Columns (Plan 04):** Three ransackers with PostgreSQL subqueries added to Source model and whitelisted. View headers use existing `table_sort_link` pattern with arrows and aria attributes. 9 integration tests cover all 3 columns in both directions plus NULL handling.
