# Concerns

## Technical Debt

### 1. Large Files
- `lib/source_monitor/fetching/feed_fetcher.rb` (627 lines) -- The core fetch pipeline handles HTTP, parsing, item creation, adaptive intervals, retry strategies, and source updates all in one class. This is the largest single-responsibility violation.
- `lib/source_monitor/configuration.rb` (655 lines) -- Contains ~12 nested configuration classes in a single file. Each settings class could be extracted.
- `app/controllers/source_monitor/import_sessions_controller.rb` (792 lines) -- The OPML import wizard controller handles all 5 wizard steps, file parsing, health checks, selection management, and bulk operations.
- `lib/source_monitor/items/item_creator.rb` -- Large item creation file (based on coverage baseline entry count).
- `config/coverage_baseline.json` (2329 lines) -- This file itself is very large, indicating significant uncovered code.

### 2. Coverage Baseline Gaps
The `config/coverage_baseline.json` catalogs uncovered lines. Particularly notable gaps:
- `lib/source_monitor/items/item_creator.rb` -- Hundreds of uncovered branch lines
- `lib/source_monitor/fetching/feed_fetcher.rb` -- Extensive uncovered branches
- `lib/source_monitor/configuration.rb` -- Many configuration edge cases untested
- `lib/source_monitor/dashboard/queries.rb` -- Dashboard query logic largely uncovered
- `lib/source_monitor/realtime/broadcaster.rb` -- Broadcasting logic has gaps
- `lib/source_monitor/scraping/bulk_source_scraper.rb` -- Bulk scraping coverage gaps
- `lib/source_monitor/analytics/sources_index_metrics.rb` -- Analytics largely uncovered

### 3. LogEntry Hard-coded Table Name
In `app/models/source_monitor/log_entry.rb` line 6: `self.table_name = "sourcemon_log_entries"` -- This bypasses the configurable table name prefix system that all other models use via `ModelExtensions.register`. The table name is hard-coded despite the engine supporting custom prefixes.

### 4. `lib/source_monitor.rb` Entry Point Complexity
The main entry point has 102+ require statements loaded eagerly. This means all engine code is loaded at boot regardless of what features the host app uses. No autoloading or lazy-loading strategy.

## Architectural Risks

### 1. PostgreSQL Lock-in
The `Scheduler` uses `FOR UPDATE SKIP LOCKED` (PostgreSQL-specific locking), and queries use `NULLS FIRST`/`NULLS LAST` ordering. The engine will not work with MySQL or SQLite. This is documented nowhere in the gemspec constraints.

### 2. In-Memory Metrics Without Persistence
`SourceMonitor::Metrics` stores counters and gauges in module-level instance variables (`@counters`, `@gauges`). These are:
- Lost on process restart
- Not shared across workers/processes
- Not suitable for production monitoring

### 3. Scraping State Management
`SourceMonitor::Scraping::State` tracks in-flight scrapes but the mechanism (cache/memory) is fragile. In multi-process deployments, this could lead to over-enqueuing or under-enqueuing of scrape jobs.

### 4. Optional Dependency Loading
Solid Queue, Solid Cable, Turbo, and Ransack are loaded with `rescue LoadError`. This means the engine could silently fail to load core functionality without clear error messages to the host app developer.

### 5. No Database Index Verification
24 migration files create the schema incrementally. There is no single-schema check to verify all expected indexes exist after migration.

## Security Considerations

### 1. No Built-in Authentication
The engine relies entirely on the host app for authentication. The `Security::Authentication` module provides hooks but no default protection. An unconfigured engine is accessible to anyone who can reach the mount path.

### 2. Fallback User Creation in Import Controller
`ImportSessionsController#create_guest_user` (lines 416-429) can create a `User` record in the host app's database when no authentication is configured. This is a defensive fallback but could be unexpected behavior.

### 3. Parameter Sanitization Scope
`Security::ParameterSanitizer` uses `ActionView::Base.full_sanitizer` which strips all HTML. This is broad but may not catch all injection vectors (e.g., URL-based attacks, header injection via custom_headers).

### 4. Custom Headers Passthrough
Source `custom_headers` are stored as JSONB and passed to HTTP requests (`FeedFetcher#request_headers`). Malicious header values could potentially be used for SSRF or header injection if not properly validated.

## Performance Considerations

### 1. N+1 Query Risk in Dashboard
`Dashboard::Queries` performs multiple database queries for stats, recent activity, quick actions, job metrics, and fetch schedules. The controller assembles all of these synchronously.

### 2. Large OPML File Handling
The OPML import parses entire files in memory (`Nokogiri::XML(content)`). Large OPML files with thousands of entries could cause memory pressure.

### 3. Bulk Scrape Operations
`BulkSourceScraper` enqueues individual `ScrapeItemJob` for each item. For sources with thousands of items, this could flood the job queue.

### 4. Coverage Baseline File
The `config/coverage_baseline.json` at 2329 lines is parsed at test time and represents significant technical debt in test coverage.

## Operational Risks

### 1. No Health Check Endpoint Documentation
The `/health` endpoint exists but its response format and behavior are not documented.

### 2. Stalled Fetch Recovery
The `StalledFetchReconciler` runs within the `Scheduler`, but if the scheduler itself stalls, there is no external recovery mechanism.

### 3. Circuit Breaker State in Database
Fetch circuit breaker state (`fetch_circuit_opened_at`, `fetch_circuit_until`) is stored on the `Source` model. This means circuit breaker resets require database writes, and a failing database connection prevents circuit recovery.

## Dependency Risks

### 1. ruby-readability (~> 0.7)
This gem appears to be minimally maintained. The `0.7.x` line is old. It depends on Nokogiri which receives frequent security updates, creating a transitive dependency management burden.

### 2. Nokolexbor (~> 0.5)
Native extension gem with C bindings to the Lexbor HTML parser. Platform-specific builds could cause deployment issues, especially on less common architectures.

### 3. Feedjira Wide Version Range
`>= 3.2, < 5.0` allows major version bumps that could introduce breaking API changes.

### 4. Ruby >= 3.4.0 Minimum
This is an aggressive minimum that excludes many production Ruby installations still on 3.2.x or 3.3.x.
