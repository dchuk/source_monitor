---
phase: 5
plan_count: 3
status: complete
started: 2026-02-22
completed: 2026-02-22
total_tests: 4
passed: 4
skipped: 0
issues: 2
issues_fixed: 2
---

## Automated Verification (Pre-UAT)

All automated checks passed before presenting manual checkpoints:

| Check | Method | Result |
|-------|--------|--------|
| Full test suite (1175 runs, 3683 assertions) | `bin/rails test` | PASS |
| Sources controller tests (21 runs, 140 assertions) | Targeted test run | PASS |
| Enqueuer + ScrapeItemJob tests (18 runs, 56 assertions) | Targeted test run | PASS |
| Word count + backfill tests (47 runs, 139 assertions) | Targeted test run | PASS |
| RuboCop (423 files) | `bin/rubocop` | PASS (0 offenses) |
| PER_PAGE = 25 | `rails runner` | PASS |
| Ransackable attributes include all filter columns | `rails runner` | PASS |
| min_scrape_interval default = 1.0, configurable | `rails runner` | PASS |
| Schema has word count + min_scrape_interval columns | `rails runner` | PASS |
| Word count computation (split on whitespace) | `rails runner` | PASS |
| Backfill rake task registered | `rails -T` | PASS |
| N+1 fix: includes(:item_content) in _details.html.erb | grep | PASS |
| Browser: pagination controls visible | agent-browser | PASS |
| Browser: filter dropdowns present (Status, Health, Format, Adapter) | agent-browser | PASS |
| Browser: Avg Words column in sources table | agent-browser | PASS |
| Browser: Words column in items table | agent-browser | PASS |
| Browser: Words column in source detail items table | agent-browser | PASS |
| Browser: Feed/Scraped Word Count in item detail | agent-browser | PASS |

## Manual Checkpoints

### P01-T1: Sources Pagination & Filtering UX

**Plan:** Plan 01 -- Sources Pagination & Column Filtering

**Scenario:** Navigate to http://localhost:3002/source_monitor/sources. Verify the pagination controls and filter dropdowns look correct and work interactively. Try selecting a filter (e.g., Health = "Healthy") and confirm the table updates. Try paginating with a filter active to confirm filters persist.

**Expected:** Pagination prev/next controls below table, dropdown filters auto-submit on change, active filter shown as badge with clear link, filters preserved across page navigation.

**Result:** PASS (with minor issue: OPML import alert squished against filter row — needs spacing)
**Issue:** P01-T1-I1 (minor): Recent OPML import alert has insufficient vertical spacing between filter controls row and the alert banner. They appear squished together.

---

### P01-T2: Filter Clear and Search Composition

**Plan:** Plan 01 -- Sources Pagination & Column Filtering

**Scenario:** On the sources page, apply a text search (e.g., search for a partial source name) AND a dropdown filter simultaneously. Verify the results show the intersection. Then clear one filter using the badge clear link and verify results update.

**Expected:** Combined text + dropdown filters return intersection. Badge clear links remove individual filters. Clearing all filters returns full list.

**Result:** PASS

---

### P03-T1: Word Count Display with Data

**Plan:** Plan 03 -- Word Count Metrics & Display

**Scenario:** Run the backfill task (`bin/rails app:source_monitor:backfill_word_counts` in test/dummy) if any items have been scraped, then refresh the sources page. Check that Avg Words shows numeric values for sources with scraped items. Click into a source and item to verify word counts display as numbers instead of dashes.

**Expected:** Sources with scraped content show numeric avg word counts. Items with scraped_content show numeric word counts in all views. Items without content show "—".

**Result:** ISSUE
**Issue:** P03-T1-I1 (major): Sources table should show avg feed word count AND avg scraped word count as separate columns (not a single "Avg Words"). Items tables should show individual feed word count AND scraped word count as separate columns (not a single "Words"). Purpose: easily compare feed vs scraped to determine if scraping should be enabled for new sources (low feed word count = needs scraping).

---

### P02-T1: Rate Limiting Configuration

**Plan:** Plan 02 -- Per-Source Scrape Rate Limiting

**Scenario:** Open a Rails console (`bin/rails console` in test/dummy) and verify: (1) `SourceMonitor.config.scraping.min_scrape_interval` returns `1.0`, (2) You can set a source's min_scrape_interval: `s = SourceMonitor::Source.first; s.update(min_scrape_interval: 30.0); s.reload.min_scrape_interval` returns `30.0`.

**Expected:** Global default is 1.0s. Per-source override persists correctly as a decimal value.

**Result:** PASS (verified programmatically: global=1.0, per-source set/reset works, nil falls back to global)
