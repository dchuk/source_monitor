# Phase 5: Source Enhancements — Context

Gathered: 2026-02-22
Calibration: architect

## Phase Boundary
Add pagination and column filtering to sources index, per-source scraping rate limit with time-based throttling, and word count metrics for items and sources.

## Decisions

### Source Filtering Scope
- Full column filtering: text search on name/URL plus dropdown filters for status, health_status, feed_type, and scraper_adapter
- Use Ransack q[] params in URL — same pattern as items index. Bookmarkable, refresh-safe
- Follow existing items index pattern for Ransack integration

### Rate Limiting Storage & Behavior
- Derive last-scrape timestamp from scrape_logs (MAX(started_at) per source) — no new columns or cache infra needed
- When rate-limited: re-enqueue the job with delay (remaining interval). Scrape always happens, just deferred
- Default minimum interval: 1 second between scrapes per source
- Configurable per-source: new `min_scrape_interval` column on Source, overrides global default from ScrapingSettings
- Global default set via `ScrapingSettings.min_scrape_interval` config option

### Word Count Scope & Display
- Track both scraped_word_count and feed_word_count as separate columns on item_contents
- Scraped content already cleaned by readability parser — count words directly (split on whitespace)
- Feed content/summary may contain HTML — strip tags before counting
- Display everywhere: items index table, source detail items table, item detail page, source index (avg word count column)
- Backfill existing records via rake task or migration

### Pagination Defaults
- Default 25 per page for sources index
- Configurable via `per_page` URL param (user can override in URL)
- Use existing SourceMonitor::Pagination::Paginator class (same as ItemsController)
- Prev/next page controls (same pattern as items/index.html.erb)

### Open (Claude's discretion)
- Pagination controls layout: match items index placement (bottom of table)
- Per-page param capped at a reasonable max (100) to prevent abuse
- Word count display format: plain integer, no thousands separator needed for typical article lengths

## Deferred Ideas
None
