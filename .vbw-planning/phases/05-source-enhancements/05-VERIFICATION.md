---
phase: 5
tier: deep
result: PARTIAL
passed: 29
failed: 1
total: 30
date: 2026-02-22
---

## Plan 01: Sources Pagination & Column Filtering (05-01 worktree)

### Must-Have Checks

| # | Truth/Condition | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | Sources index returns paginated results (25/page default, per_page capped at 100) | PASS | `PER_PAGE = 25`, Paginator.new wraps `@q.result` in SourcesController#index; test "caps per_page at 100" passes |
| 2 | Prev/next pagination controls rendered below sources table matching items index pattern | PASS | sources/index.html.erb:207-231: prev/next with disabled states, "Page N" text, turbo_frame data attr |
| 3 | Ransack dropdown filters for status, health_status, feed_format, scraper_adapter present | PASS | index.html.erb:25-41: active_eq, health_status_eq, feed_format_eq, scraper_adapter_eq selects with onchange submit |
| 4 | Text search field searches name + feed_url + website_url via Ransack q[] params | PASS | SEARCH_FIELD = :name_or_feed_url_or_website_url_cont used in form |
| 5 | Filter state preserved across pagination (q[] params passed through page links) | PASS | Lines 213-217: prev/next params include @search_params and per_page; test "pagination preserves filter params" passes |
| 6 | Source.ransackable_attributes includes status, health_status, feed_format, scraper_adapter | PASS | source.rb:65-66: `%w[... active health_status feed_format scraper_adapter]` |
| 7 | All existing tests pass, new tests cover pagination and filter behavior | PASS | 21 runs, 140 assertions, 0 failures; 8 new tests (pagination + filter scenarios) |
| 8 | RuboCop zero offenses | PASS | 0 offenses on .rb files; ERB files have known RuboCop parser limitation (pre-existing, not code issues) |

**Plan 01 Result: PASS (8/8)**

---

## Plan 02: Per-Source Scrape Rate Limiting (05-02 worktree)

### Must-Have Checks

| # | Truth/Condition | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | Migration adds min_scrape_interval column (decimal, seconds) to sourcemon_sources with default nil | PASS | 20260222120000_add_min_scrape_interval_to_sources.rb: `decimal, precision: 10, scale: 2, null: true, default: nil` |
| 2 | ScrapingSettings has min_scrape_interval with DEFAULT_MIN_SCRAPE_INTERVAL = 1.0 | PASS | scraping_settings.rb: `DEFAULT_MIN_SCRAPE_INTERVAL = 1.0`, attr_accessor, normalize_numeric_float setter |
| 3 | Enqueuer derives last-scrape timestamp from scrape_logs MAX(started_at) per source | PASS | enqueuer.rb:133: `source.scrape_logs.maximum(:started_at)` |
| 4 | When rate-limited, ScrapeItemJob re-enqueues itself with set(wait:) for remaining interval | PASS | scrape_item_job.rb:23-24: `self.class.set(wait: remaining.seconds).perform_later(item_id)`; clears in-flight first |
| 5 | Per-source min_scrape_interval overrides global ScrapingSettings.min_scrape_interval when present | PASS | enqueuer.rb:130 and scrape_item_job.rb:43: `source.min_scrape_interval \|\| SourceMonitor.config.scraping.min_scrape_interval` |
| 6 | All existing enqueuer and scrape_item_job tests pass, new tests cover rate limit behavior | PASS | 18 runs, 56 assertions, 0 failures; 6 Enqueuer + 3 ScrapeItemJob time rate limiting tests; full suite 1154 runs, 0 failures |
| 7 | RuboCop zero offenses | PASS | 0 offenses on enqueuer.rb, scraping_settings.rb, scrape_item_job.rb |

**Plan 02 Result: PASS (7/7)**

---

## Plan 03: Word Count Metrics & Display (05-03 worktree)

### Must-Have Checks

| # | Truth/Condition | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | Migration adds scraped_word_count and feed_word_count integer columns to sourcemon_item_contents | PASS | 20260222194201_add_word_counts_to_item_contents.rb: two integer columns; schema.rb confirms |
| 2 | ItemContent before_save callback computes word counts (scraped from whitespace-split, feed from HTML-stripped) | PASS | item_content.rb:11,21-39: before_save :compute_word_counts; scraped uses split, feed uses ActionView::Base.full_sanitizer.sanitize then split |
| 3 | Word counts displayed on items index table, source detail items table, item detail page | PARTIAL | items/index.html.erb:67,116: Words column ✓; items/_details.html.erb:134-135: Feed/Scraped Word Count ✓; sources/_details.html.erb:284,321: Words column ✓; **BUT** _details.html.erb creates own `items` query (line 5) WITHOUT `includes(:item_content)` — N+1 queries triggered for source detail items table |
| 4 | Avg word count column displayed on sources index _row partial | PASS | sources/index.html.erb:123: "Avg Words" column header; sources/_row.html.erb:71: `avg_words_map[source.id]&.round \|\| "—"` |
| 5 | Rake task source_monitor:backfill_word_counts populates existing records | PASS | source_monitor_tasks.rake:5-16: iterates ItemContent.find_each, calls save!, prints progress; backfill_word_counts_task_test.rb verifies population |
| 6 | All existing tests pass, new tests cover word count computation and display | PASS | Full suite: 1158 runs, 3616 assertions, 0 failures, 0 errors, 0 skips; 7+ new tests covering computation, display, avg, backfill |
| 7 | RuboCop zero offenses | PASS | 0 offenses on item_content.rb, source.rb, source_monitor_tasks.rake |

**Plan 03 Result: PARTIAL (6/7 — N+1 in source detail items table)**

---

## Artifact Checks

| Artifact | Exists | Contains | Status |
|----------|--------|----------|--------|
| db/migrate/20260222120000_add_min_scrape_interval_to_sources.rb | YES | decimal, precision: 10, scale: 2, null: true, sourcemon_sources | PASS |
| db/migrate/20260222194201_add_word_counts_to_item_contents.rb | YES | scraped_word_count :integer, feed_word_count :integer, sourcemon_item_contents | PASS |
| lib/source_monitor/configuration/scraping_settings.rb | YES | DEFAULT_MIN_SCRAPE_INTERVAL = 1.0, normalize_numeric_float, reset! | PASS |
| lib/source_monitor/scraping/enqueuer.rb | YES | time_rate_limited?, deferred? on Result, re-enqueue with wait: | PASS |
| app/jobs/source_monitor/scrape_item_job.rb | YES | time_until_scrape_allowed, clear_inflight! on deferral, re-enqueue | PASS |
| app/models/source_monitor/item_content.rb | YES | before_save :compute_word_counts, total_word_count, scraped/feed word count methods | PASS |
| app/models/source_monitor/source.rb (05-01) | YES | ransackable_attributes includes active, health_status, feed_format, scraper_adapter | PASS |
| app/models/source_monitor/source.rb (05-03) | YES | avg_word_count method using joins(:item_content).average() | PASS |
| app/controllers/source_monitor/sources_controller.rb (05-01) | YES | PER_PAGE=25, Paginator integration, pagination variables | PASS |
| app/controllers/source_monitor/sources_controller.rb (05-03) | YES | avg_word_counts query (single grouped SQL, no N+1), includes(:item_content) in show | PASS |
| lib/tasks/source_monitor_tasks.rake | YES | backfill_word_counts task, find_each, save!, progress output | PASS |
| test/controllers/source_monitor/sources_controller_test.rb (05-01) | YES | 8 new pagination+filter tests | PASS |
| test/lib/source_monitor/scraping/enqueuer_test.rb (05-02) | YES | 6 time rate limiting tests | PASS |
| test/jobs/source_monitor/scrape_item_job_test.rb (05-02) | YES | 3 time rate limiting tests | PASS |
| test/models/source_monitor/item_content_test.rb (05-03) | YES | 7+ word count computation tests | PASS |
| test/tasks/backfill_word_counts_task_test.rb (05-03) | YES | backfill population test | PASS |

---

## Anti-Pattern Scan

| Pattern | Found | Location | Severity |
|---------|-------|----------|----------|
| N+1 query | YES | sources/_details.html.erb:5 — `items = source.items.recent.limit(preview_limit)` without includes(:item_content); Words column at line 321 triggers N+1 | HIGH |
| Hard-coded table names | YES | source.rb avg_word_count uses `sourcemon_item_contents`; sources_controller uses `sourcemon_items` in avg_word_counts query | LOW (pre-existing pattern, noted in CONCERNS.md) |
| Deferred result bypasses item lock (Plan 02) | PARTIAL | Enqueuer re-enqueues without marking item pending — this is intentional (deferred = not yet ready), correct behavior | OK |

---

## Cross-Plan Integration Assessment

| From | To | Via | Status |
|------|----|-----|--------|
| Plan 01 (sources/index.html.erb: filters+pagination) | Plan 03 (sources/index.html.erb: Avg Words column) | Both forked from commit acb451e — merge required | CONFLICT EXPECTED |
| Plan 01 (sources_controller.rb: PER_PAGE+Paginator) | Plan 03 (sources_controller.rb: avg_word_counts query) | Both forked from commit acb451e — merge required | CONFLICT EXPECTED |
| Plan 01 (source.rb: expanded ransackable_attributes) | Plan 03 (source.rb: avg_word_count method) | Both forked from commit acb451e — merge required | CONFLICT EXPECTED |
| Plan 01 (sources/_row.html.erb: unchanged) | Plan 03 (sources/_row.html.erb: avg_words_map cell) | Plan 01 doesn't touch _row.html.erb — no conflict | PASS |
| Plan 02 (ScrapeItemJob: time rate limiting) | Plans 01, 03 (no ScrapeItemJob changes) | Independent files, no conflict | PASS |

**Merge notes:** Plans 01 and 03 conflict on three files. All conflicts are additive (Plan 01 adds X, Plan 03 adds Y to same file). When merging sequentially (Plan 01 first, then Plan 03 on top), the 05-03 worktree's sources/index.html.erb will be missing pagination controls and dropdown filters — the merge must incorporate Plan 01's changes into Plan 03's versions.

---

## Convention Compliance

| Convention | File | Status | Detail |
|-----------|------|--------|--------|
| No N+1 queries | sources/_details.html.erb | FAIL | items query lacks includes(:item_content) — see Anti-Pattern Scan |
| Shallow jobs (no business logic) | scrape_item_job.rb | PASS | time check is minimal; delegates to ItemScraper |
| RuboCop zero offenses | All .rb files | PASS | Confirmed 0 offenses on all modified .rb files |
| Test every controller action / model method | All plans | PASS | New public methods and controller behaviors are tested |
| Configuration reset in tests | Enqueuer+ScrapeItemJob tests | PASS | SourceMonitor.configure blocks used; reset_configuration! in test_helper |
| Engine migration conventions (sourcemon_ prefix) | Both migrations | PASS | sourcemon_sources and sourcemon_item_contents tables used |

---

## Summary

**Tier:** Deep
**Result:** PARTIAL
**Passed:** 29/30
**Failed:** [Plan 03 Must-Have #3 — N+1 in sources/_details.html.erb word count column]

### Per-Plan Verdict
| Plan | Result | Notes |
|------|--------|-------|
| Plan 01: Pagination & Column Filtering | PASS | All 8 must-haves met; tests pass; clean implementation |
| Plan 02: Per-Source Scrape Rate Limiting | PASS | All 7 must-haves met; comprehensive tests; RuboCop clean |
| Plan 03: Word Count Metrics & Display | PARTIAL | Display works on all views but sources/_details.html.erb triggers N+1 for Words column (partial `items` query lacks includes) |

### Critical Issue
**N+1 in sources/_details.html.erb** (Plan 03):
- File: `app/views/source_monitor/sources/_details.html.erb:5`
- Root cause: `<% items = source.items.recent.limit(preview_limit) %>` does not include `:item_content`
- Effect: Each `item.item_content&.scraped_word_count` at line 321 triggers a separate query (up to 10 per page view)
- Fix: Add `.includes(:item_content)` to the query at line 5: `source.items.recent.includes(:item_content).limit(preview_limit)`

### Cross-Plan Integration
Plans 01 and 03 have expected merge conflicts on `sources/index.html.erb`, `sources_controller.rb`, and `source.rb`. Changes are additive and non-contradictory. When merging these plans into main, the merge must:
1. `source.rb`: Retain expanded ransackable_attributes (Plan 01) + add avg_word_count method (Plan 03)
2. `sources_controller.rb`: Retain PER_PAGE/Paginator (Plan 01) + add avg_word_counts query (Plan 03)  
3. `sources/index.html.erb`: Combine dropdown filters+pagination controls (Plan 01) + Avg Words column (Plan 03)
