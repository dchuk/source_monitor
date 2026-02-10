# Architecture

## System Overview

SourceMonitor is a mountable Rails 8 engine that ingests RSS, Atom, and JSON feeds, scrapes full article content, and surfaces Solid Queue-powered dashboards for monitoring and remediation. It is packaged as a RubyGem and mounted into a host Rails application.

## Architecture Pattern

**Mountable Rails Engine** with `isolate_namespace SourceMonitor`. The engine:
- Provides its own models, controllers, views, jobs, and frontend assets
- Uses its own `ApplicationRecord`, `ApplicationController`, and `ApplicationJob` base classes
- Namespaces all database tables under a configurable prefix (default: `sourcemon_`)
- Registers its own routes, asset paths, and initializers

## Core Domain Modules

### 1. Feed Fetching (`lib/source_monitor/fetching/`)
The primary data ingestion pipeline:
- `FeedFetcher` -- Orchestrates HTTP request, feed parsing via Feedjira, item creation, adaptive interval scheduling, and retry policies
- `FetchRunner` -- Entry point for enqueuing fetch jobs; handles concurrency control
- `FetchError` hierarchy -- Typed error classes (TimeoutError, ConnectionError, HTTPError, ParsingError)
- `RetryPolicy` -- Exponential backoff with circuit breaker pattern
- `StalledFetchReconciler` -- Recovers stalled fetch jobs

### 2. Content Scraping (`lib/source_monitor/scraping/` + `lib/source_monitor/scrapers/`)
Pluggable content extraction system:
- `Scrapers::Base` -- Abstract adapter contract; subclasses implement `#call` returning a `Result` struct
- `Scrapers::Readability` -- Default adapter using ruby-readability
- `Scraping::ItemScraper` -- Orchestrator that resolves adapter, executes scrape, persists results
- `Scraping::BulkSourceScraper` -- Batch scraping across all items for a source
- `Scraping::Enqueuer` -- Manages scrape job queuing with in-flight throttling
- `Scraping::State` -- Tracks in-flight scrape state via cache/memory

### 3. Health Monitoring (`lib/source_monitor/health/`)
Source health tracking system:
- `SourceHealthMonitor` -- Computes health status from recent fetch history (sliding window)
- `SourceHealthCheck` -- One-off health probe for a source URL
- `ImportSourceHealthCheck` -- Variant for import wizard health checks
- `SourceHealthReset` -- Resets health status for a source
- Configurable thresholds: healthy (0.8), warning (0.5), auto-pause (0.2)

### 4. Scheduling (`lib/source_monitor/scheduler.rb`)
- `Scheduler` -- Periodic job that finds sources due for fetch using `FOR UPDATE SKIP LOCKED`
- Adaptive fetch interval algorithm (increase/decrease factors, jitter)
- Integrates with `StalledFetchReconciler` for recovery

### 5. Event System (`lib/source_monitor/events.rb`)
- Typed event structs: `ItemCreatedEvent`, `ItemScrapedEvent`, `FetchCompletedEvent`
- Callback-based dispatch with error isolation per handler
- Item processor pipeline for custom host-app processing
- Registration via `SourceMonitor.config.events.after_*` DSL

### 6. Configuration (`lib/source_monitor/configuration.rb`)
Rich nested configuration object with sub-configs:
- `HTTPSettings` -- timeout, retries, user agent, proxy, headers
- `ScraperRegistry` -- pluggable adapter registration
- `RetentionSettings` -- item retention days, max items, strategy (destroy/soft_delete)
- `RealtimeSettings` -- adapter selection (solid_cable/redis/async)
- `FetchingSettings` -- adaptive interval tuning
- `HealthSettings` -- health window and threshold configuration
- `AuthenticationSettings` -- pluggable authentication/authorization handlers
- `ScrapingSettings` -- concurrency limits
- `Events` -- callback registration
- `Models` -- concern injection and custom validation registration

### 7. Model Extensions (`lib/source_monitor/model_extensions.rb`)
Dynamic model customization system:
- Host apps can inject concerns and validations into engine models at configuration time
- `ModelExtensions.register(model_class, key)` -- called in each model class body
- `ModelExtensions.reload!` -- re-applies all extensions (called on configuration change)
- Manages table name assignment from configurable prefix

### 8. Real-time Broadcasting (`lib/source_monitor/realtime/`)
- `Realtime::Adapter` -- Configures Action Cable based on selected adapter
- `Realtime::Broadcaster` -- Broadcasts source/item updates and toast notifications
- `Dashboard::TurboBroadcaster` -- Wires dashboard stat updates to Turbo Streams

### 9. Setup/Installation System (`lib/source_monitor/setup/`)
Comprehensive host-app installation workflow:
- `Setup::CLI` -- Command-line interface for setup
- `Setup::Workflow` -- Orchestrates multi-step installation
- `Setup::Requirements` / `Setup::Detectors` -- System requirement checks
- `Setup::GemfileEditor` / `Setup::BundleInstaller` / `Setup::NodeInstaller` -- Dependency installation
- `Setup::InstallGenerator` -- Rails generator for migrations, routes, initializer
- `Setup::Verification::Runner` -- Post-install verification (Solid Queue, Action Cable)

### 10. OPML Import Wizard (`app/controllers/source_monitor/import_sessions_controller.rb`)
Multi-step wizard for bulk feed import:
- 5-step flow: upload -> preview -> health_check -> configure -> confirm
- State persisted in `ImportSession` model with JSONB columns
- Health check jobs run asynchronously with Turbo Stream progress updates
- Bulk settings applied to all imported sources

## Data Model

```
Source (sourcemon_sources)
  |-- has_many Item (sourcemon_items)
  |     |-- has_one ItemContent (sourcemon_item_contents) [separate table for large content]
  |     |-- has_many ScrapeLog (sourcemon_scrape_logs)
  |     +-- has_many LogEntry (sourcemon_log_entries) [polymorphic]
  |-- has_many FetchLog (sourcemon_fetch_logs)
  |-- has_many HealthCheckLog (sourcemon_health_check_logs)
  +-- has_many LogEntry (sourcemon_log_entries)

LogEntry (sourcemon_log_entries)
  |-- delegated_type :loggable -> FetchLog | ScrapeLog | HealthCheckLog

ImportSession (sourcemon_import_sessions)
  +-- JSONB columns for wizard state

ImportHistory (sourcemon_import_histories)
  +-- Records completed imports
```

## Job Architecture

All jobs inherit from `SourceMonitor::ApplicationJob` which inherits from the host app's `ApplicationJob` (or `ActiveJob::Base`).

| Job | Queue | Purpose |
|-----|-------|---------|
| `ScheduleFetchesJob` | fetch | Recurring: triggers Scheduler to find and enqueue due sources |
| `FetchFeedJob` | fetch | Fetches a single source's feed, creates items |
| `ScrapeItemJob` | scrape | Scrapes content for a single item |
| `SourceHealthCheckJob` | fetch | Runs health check for a source |
| `ImportSessionHealthCheckJob` | fetch | Health checks during OPML import wizard |
| `ImportOpmlJob` | fetch | Bulk-creates sources from OPML import |
| `LogCleanupJob` | fetch | Recurring: prunes old log entries |
| `ItemCleanupJob` | fetch | Recurring: prunes old items per retention policy |

Queue names are configurable via `config.fetch_queue_name` and `config.scrape_queue_name`.

## Security Architecture

- `Security::Authentication` -- Pluggable authentication via handler callbacks (symbol method names or callables)
- `Security::ParameterSanitizer` -- HTML sanitization of all user inputs via `ActionView::Base.full_sanitizer`
- `Models::Sanitizable` -- Concern that sanitizes string and hash model attributes before validation
- `Models::UrlNormalizable` -- URL normalization and validation concern
- `SanitizesSearchParams` -- Controller concern for search parameter sanitization
- CSRF protection enabled (`protect_from_forgery with: :exception`)
- No built-in user model -- delegates to host app

## Instrumentation & Metrics

- `Instrumentation` -- Emits `ActiveSupport::Notifications` events for fetch lifecycle
- `Metrics` -- In-memory counters and gauges, populated via notification subscribers
- Events: `source_monitor.fetch.start`, `source_monitor.fetch.finish`, `source_monitor.scheduler.run`, `source_monitor.items.duplicate`, `source_monitor.items.retention`
