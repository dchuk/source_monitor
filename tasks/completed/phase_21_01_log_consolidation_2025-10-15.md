# Phase 21.01 – Log Consolidation Notes (2025-10-15)

## Existing UI Inventory

- `app/views/source_monitor/fetch_logs/index.html.erb`
  - Columns: Started timestamp, Source link, HTTP status, Result badge, item delta summary, view link.
  - Page-level filter: status (`All`, `Successes`, `Failures`).
  - Metadata surfaced via badges and counts; table limited to 50 rows.
- `app/views/source_monitor/fetch_logs/show.html.erb`
  - Summary stack with source, HTTP, success flag, duration, item counts, timestamps, job id.
  - Secondary panels for error details (message, backtrace), HTTP headers (pretty JSON), metadata.
- `app/views/source_monitor/scrape_logs/index.html.erb`
  - Columns: Started timestamp, Item link, Source link, Result badge, duration, view link.
  - Same status filter bar; duration replaces item delta metrics.
- `app/views/source_monitor/scrape_logs/show.html.erb`
  - Summary with item/source links, adapter, HTTP, success flag, duration, content length, timestamps.
  - Panels for error details and metadata.
- Navigation (`app/views/layouts/source_monitor/application.html.erb`) now surfaces a single **Logs** entry pointing at the consolidated index.

## Combined Layout Outline

- Single "Logs" index with shared table:
  - Columns: Started, Type badge, Subject (item or source), Source link, HTTP/adapter summary, Result badge with inline error text, Metrics (fetch deltas or scrape duration), Detail link.
  - Rows expose `data-log-row` identifiers (`fetch-<id>` / `scrape-<id>`) for tests and Turbo.
- Unified filter bar:
  - Status toggle (All/Successes/Failures) and Log Type toggle (All Logs/Fetch Logs/Scrape Logs).
  - Search form includes free-text box, timeframe select (24h/7d/30d), explicit start range inputs, and numeric `source_id`/`item_id` filters.
  - Pagination uses `SourceMonitor::Pagination::Paginator` with Prev/Next links and a page indicator span.
- Detail views remain type-specific (fetch/scrape) but back links now route through `source_monitor.logs_path` with the appropriate `log_type` preset.
- Controller composes `SourceMonitor::Logs::Query` + `TablePresenter`; no shared concern is needed.
