# Index

Cross-referenced index of key findings across all mapping documents.

## Quick Reference

| Document | Focus | Key Finding |
|----------|-------|-------------|
| [STACK.md](STACK.md) | Technology choices | Rails 8.1.1 engine, Ruby 3.4+, PostgreSQL, Solid Queue, Tailwind 3 |
| [DEPENDENCIES.md](DEPENDENCIES.md) | Dependency analysis | 14 runtime gems, PG-only, optional deps loaded silently |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design | 10 domain modules, event-driven, pluggable scrapers |
| [STRUCTURE.md](STRUCTURE.md) | Directory layout | ~324 Ruby files, 124 tests, 24 migrations |
| [CONVENTIONS.md](CONVENTIONS.md) | Code style | Rails omakase, frozen strings, Struct-based results |
| [TESTING.md](TESTING.md) | Test infrastructure | Minitest, parallel, SimpleCov branch coverage, nightly profiling |
| [CONCERNS.md](CONCERNS.md) | Risks & debt | Large files, PG lock-in, coverage gaps, no default auth |
| [PATTERNS.md](PATTERNS.md) | Recurring patterns | Service objects, adapter pattern, event callbacks, Turbo Streams |

## Key Entry Points

| Purpose | File | Notes |
|---------|------|-------|
| Gem entry point | `lib/source_monitor.rb` | 102+ require statements, module definition |
| Engine definition | `lib/source_monitor/engine.rb` | Initializers, asset registration |
| Configuration DSL | `lib/source_monitor/configuration.rb` | 12 nested settings classes |
| Routes | `config/routes.rb` | 24 lines, RESTful resources |
| Main model | `app/models/source_monitor/source.rb` | Core domain entity |
| Dashboard | `app/controllers/source_monitor/dashboard_controller.rb` | Landing page |
| Fetch pipeline | `lib/source_monitor/fetching/feed_fetcher.rb` | Core data ingestion |
| Scrape pipeline | `lib/source_monitor/scraping/item_scraper.rb` | Content extraction orchestrator |
| Scheduler | `lib/source_monitor/scheduler.rb` | Periodic fetch scheduling |
| JS entry | `app/assets/javascripts/source_monitor/application.js` | Stimulus app setup |
| CSS entry | `app/assets/stylesheets/source_monitor/application.tailwind.css` | Tailwind input |
| Test entry | `test/test_helper.rb` | Test infrastructure setup |

## Data Model Reference

| Model | Table | Key Relationships |
|-------|-------|-------------------|
| `Source` | `sourcemon_sources` | has_many: items, fetch_logs, scrape_logs, health_check_logs, log_entries |
| `Item` | `sourcemon_items` | belongs_to: source; has_one: item_content; has_many: scrape_logs, log_entries |
| `ItemContent` | `sourcemon_item_contents` | belongs_to: item (separate table for large scraped content) |
| `FetchLog` | `sourcemon_fetch_logs` | belongs_to: source; has_one: log_entry (polymorphic) |
| `ScrapeLog` | `sourcemon_scrape_logs` | belongs_to: item, source; has_one: log_entry (polymorphic) |
| `HealthCheckLog` | `sourcemon_health_check_logs` | belongs_to: source; has_one: log_entry (polymorphic) |
| `LogEntry` | `sourcemon_log_entries` | delegated_type: loggable (FetchLog/ScrapeLog/HealthCheckLog) |
| `ImportSession` | `sourcemon_import_sessions` | JSONB state for wizard flow |
| `ImportHistory` | `sourcemon_import_histories` | Records completed imports |

## Job Reference

| Job Class | Queue | Schedule | Purpose |
|-----------|-------|----------|---------|
| `ScheduleFetchesJob` | fetch | Recurring | Triggers scheduler to find due sources |
| `FetchFeedJob` | fetch | On-demand | Fetches one source's feed |
| `ScrapeItemJob` | scrape | On-demand | Scrapes one item's content |
| `SourceHealthCheckJob` | fetch | On-demand | Health check for one source |
| `ImportSessionHealthCheckJob` | fetch | On-demand | Health check during OPML import |
| `ImportOpmlJob` | fetch | On-demand | Bulk creates sources from OPML |
| `LogCleanupJob` | fetch | Recurring | Prunes old log entries |
| `ItemCleanupJob` | fetch | Recurring | Prunes items per retention policy |

## Configuration Surface Area

| Section | Key Settings | Defaults |
|---------|-------------|----------|
| Queues | `fetch_queue_name`, `scrape_queue_name`, concurrency | `source_monitor_fetch`, `source_monitor_scrape`, 2 each |
| HTTP | timeout, retries, user agent, proxy, headers | 15s/5s timeout, 4 retries |
| Fetching | adaptive interval params, jitter | 5min-24hr, 1.25x increase, 0.75x decrease |
| Health | window size, thresholds, auto-pause | 20 window, 0.8/0.5/0.2 thresholds |
| Scraping | max_in_flight, max_bulk_batch | 25, 100 |
| Retention | days, max_items, strategy | nil (no auto-cleanup), :destroy |
| Realtime | adapter (solid_cable/redis/async) | solid_cable |
| Authentication | handlers, current_user_method | nil (no auth by default) |
| Models | table_name_prefix, concerns, validations | `sourcemon_` |

## Critical Cross-Cutting Concerns

1. **PG-only** (ARCHITECTURE + CONCERNS): `FOR UPDATE SKIP LOCKED` and `NULLS FIRST/LAST` SQL are PostgreSQL-specific. No other DB supported.

2. **No default auth** (ARCHITECTURE + CONCERNS): Engine mounts without authentication unless host app configures it. Import wizard has a `create_guest_user` fallback.

3. **Eager loading** (STRUCTURE + CONCERNS): All 102+ require statements in `lib/source_monitor.rb` load at boot time.

4. **Coverage debt** (TESTING + CONCERNS): `config/coverage_baseline.json` lists 2329 lines of known uncovered code, particularly in `FeedFetcher`, `ItemCreator`, `Configuration`, and `Dashboard::Queries`.

5. **Large files** (STRUCTURE + CONCERNS): `FeedFetcher` (627 lines), `Configuration` (655 lines), and `ImportSessionsController` (792 lines) are candidates for extraction.
