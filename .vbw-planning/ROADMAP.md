# Roadmap

## Milestone: polish-and-reliability

### Phases

1. [x] **Backend Fixes** -- Fix browser User-Agent default, health check status transitions, and smarter scrape rate limiting
2. [x] **Favicon Support** -- Automatically save source favicons via Active Storage with background fetch job
3. [x] **Toast Stacking** -- Cap visible toast notifications with click-to-expand for bulk operation UX
4. [x] **Bug Fixes & Polish** -- Fix OPML import warning, toast positioning, dashboard alignment, source deletion, and published column
5. [x] **Source Enhancements** -- Add pagination/filtering for sources, per-source scrape rate limiting, and word count metrics

### Phase Details

#### Phase 1: Backend Fixes

**Goal:** Fix three independent backend issues: bot-blocked feeds due to User-Agent, health check not updating status, and overly aggressive scrape limiting.

**Requirements:**
- REQ-UA-01: Change default User-Agent from "SourceMonitor/VERSION" to a browser-like string
- REQ-HC-01: After a successful manual health check on a declining/critical/warning source, trigger SourceHealthMonitor re-evaluation or directly transition status to "improving"
- REQ-SL-01: Refine max_in_flight_per_source to only count actively-running scrape jobs (not queued ones)

**Success Criteria:**
- [ ] Default UA string resembles a real browser (e.g., Mozilla/5.0 compatible)
- [ ] Successful manual health check on a declining source transitions it to improving
- [ ] Scrape limit counts only actively-running jobs, queued items don't count toward the cap
- [ ] All existing tests pass, new tests cover changed behavior
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 2: Favicon Support

**Goal:** Automatically fetch and store source favicons using Active Storage, displayed in the UI next to source names.

**Requirements:**
- REQ-FAV-01: Add has_one_attached :favicon to Source model with if defined?(ActiveStorage) guard
- REQ-FAV-02: Create FaviconFetchJob to discover favicon URL from website_url (link[rel=icon], /favicon.ico fallback)
- REQ-FAV-03: Trigger favicon fetch on source creation and periodically on successful fetches (if missing)
- REQ-FAV-04: Display favicon in source list/show views with fallback placeholder

**Success Criteria:**
- [ ] Source model has has_one_attached :favicon with Active Storage guard
- [ ] FaviconFetchJob discovers and downloads favicons from website_url
- [ ] Favicon fetched on source creation and refreshed if missing
- [ ] Favicon displayed in source views with graceful fallback
- [ ] Host apps without Active Storage don't crash
- [ ] All existing tests pass, new tests cover favicon paths
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 3: Toast Stacking

**Goal:** Replace uncapped toast notification stacking with a max-visible cap and "+N more" hover-to-expand pattern for cleaner UX during bulk operations.

**Requirements:**
- REQ-TOAST-01: Cap visible toasts at a configurable max (default: 3)
- REQ-TOAST-02: When cap exceeded, show a "+N more" badge/indicator
- REQ-TOAST-03: Hovering the notification area expands to show all stacked toasts
- REQ-TOAST-04: Individual toasts still auto-dismiss after their delay

**Success Criteria:**
- [ ] No more than 3 toasts visible simultaneously (configurable)
- [ ] Overflow indicator shows count of hidden toasts
- [ ] Hover/focus expands the stack to show all
- [ ] Auto-dismiss still works, stack count updates as toasts expire
- [ ] No regressions in existing toast behavior (inline + broadcast paths)
- [ ] RuboCop zero offenses

#### Phase 4: Bug Fixes & Polish

**Goal:** Fix five independent UI/UX bugs: spurious OPML import warning, toast notifications covering nav, dashboard table column misalignment, source deletion 500 error, and published column always showing "Unpublished".

**Requirements:**
- REQ-BF-01: Remove beforeunload/turbo:before-visit guard when OPML import is submitted (disable confirm-navigation controller on form submit)
- REQ-BF-02: Push toast notification container below the nav header (change top-4 to top-16+) so alerts don't cover menu links
- REQ-BF-03: Apply consistent column widths across all dashboard fetch schedule tables (table-fixed + explicit widths)
- REQ-BF-04: Fix source deletion 500 error — add error handling around @source.destroy, investigate dependent chain failures
- REQ-BF-05: Fix published column on items page — ensure published_at is populated from feed entry dates, fall back to created_at for display

**Success Criteria:**
- [ ] Completing an OPML import navigates to sources without a warning dialog
- [ ] Toast notifications appear below the nav header, menu links always visible
- [ ] Dashboard fetch schedule tables have aligned columns across all time brackets
- [ ] Deleting a source works without error
- [ ] Published column shows actual dates (or "ingested" fallback) instead of "Unpublished" for all items
- [ ] All existing tests pass, new tests cover changed behavior
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 5: Source Enhancements

**Goal:** Add pagination and column filtering to sources index, per-source scraping rate limit with time-based throttling, and word count metrics for items and sources.

**Requirements:**
- REQ-SE-01: Add pagination to sources index (default 25/page, configurable via per_page param) using existing Paginator class
- REQ-SE-02: Add full column filtering: text search on name/URL + dropdown filters for status, health_status, feed_type, scraper_adapter via Ransack q[] URL params
- REQ-SE-03: Add time-based per-source scrape rate limiting. Derive last-scrape from scrape_logs MAX(started_at). Re-enqueue with delay when rate-limited. Default 1s interval
- REQ-SE-04: Add per-source configurable min_scrape_interval column (overrides global default from ScrapingSettings)
- REQ-SE-05: Add scraped_word_count and feed_word_count columns to item_contents. Scraped content counted as-is (readability-cleaned). Feed content stripped of HTML before counting
- REQ-SE-06: Display word counts on items index, source detail items table, item detail page, and avg word count on sources index

**Success Criteria:**
- [ ] Sources index paginated (default 25/page) with per_page URL param and prev/next controls
- [ ] Sources filterable by text search + status/health_status/feed_type/scraper_adapter dropdowns via Ransack
- [ ] Per-source scrape rate limiting derives last-scrape from scrape_logs, re-enqueues with delay
- [ ] Source model has min_scrape_interval column overriding global ScrapingSettings default (1s)
- [ ] item_contents has scraped_word_count and feed_word_count columns with appropriate callbacks
- [ ] Word counts displayed in items index, source items table, item detail, sources index (avg)
- [ ] Backfill task populates word counts for existing records
- [ ] All existing tests pass, new tests cover all new behavior
- [ ] RuboCop zero offenses, Brakeman zero warnings

### Progress

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. Backend Fixes | Complete | 3 | 3 |
| 2. Favicon Support | Complete | 3 | 3 |
| 3. Toast Stacking | Complete | 1 | 1 |
| 4. Bug Fixes & Polish | Complete | 3 | 3 |
| 5. Source Enhancements | Complete | 3 | 3 |
