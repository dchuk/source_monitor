# Phase 1: Backend Fixes — Context

Gathered: 2026-02-20
Calibration: architect

## Phase Boundary
Fix three independent backend issues: bot-blocked feeds due to User-Agent, health check not updating status, and overly aggressive scrape limiting.

## Decisions

### Health Check Integration
- **Approach:** Hybrid -- successful health check on a degraded source (declining/critical/warning) enqueues a full fetch
- Full fetch creates a real fetch_log entry, letting SourceHealthMonitor handle status transitions naturally
- No synthetic log entries, no direct status mutation
- Only triggers on degraded sources; healthy sources skip the extra fetch
- Key files: `SourceHealthCheckJob`, `SourceHealthCheck`, `SourceHealthMonitor`

### User-Agent + HTTP Headers
- **UA strategy:** Polite bot default: `Mozilla/5.0 (compatible; SourceMonitor/VERSION; +URL)`
- **Configurable:** Expose `config.http.user_agent` (already exists as callable) with new default
- **Accept header:** Add `text/html` to Accept: `text/html, application/rss+xml, application/atom+xml, application/json;q=0.9, text/xml;q=0.8`
- **Accept-Language:** Add `en-US,en;q=0.9` as default
- **Referer:** Send source's `website_url` as Referer header in FeedFetcher requests
- **DNT:** Add `DNT: 1`
- **Per-source override:** Custom_headers on source override global defaults (current behavior, no change needed)
- Key files: `HTTP.default_headers`, `HttpSettings`, `FeedFetcher#request_headers`

### Scrape Rate Limiting
- **Approach:** Remove default limit entirely -- set `DEFAULT_MAX_IN_FLIGHT` to `nil`
- Solid Queue worker pool provides natural backpressure
- Config option `max_in_flight_per_source` remains for users who want their own cap
- The "Stopped after reaching per-source limit" message only appears when a user explicitly sets a limit
- Key files: `ScrapingSettings`, `Enqueuer#rate_limit_exhausted?`, `BulkSourceScraper`, `BulkResultPresenter`

### Open (Claude's discretion)
- Cookie handling and session persistence: out of scope for this phase
- JavaScript-rendered feeds: out of scope (would need headless browser)

## Deferred Ideas
None.
