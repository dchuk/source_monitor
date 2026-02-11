---
name: sm-architecture
description: Provides SourceMonitor engine architecture context. Use when working with engine internals, lib/ module structure, autoload organization, configuration DSL, pipelines, or any structural/organizational code in the source_monitor namespace.
allowed-tools: Read, Glob, Grep
user-invocable: false
---

# SourceMonitor Architecture

## Overview

SourceMonitor is a Rails 8 mountable engine (`SourceMonitor::Engine`). Code is split between:
- **`app/`** -- Rails conventions (models, controllers, views, jobs, concerns)
- **`lib/source_monitor/`** -- Domain logic, configuration, pipelines, utilities

The engine uses **Ruby autoload** (not Zeitwerk) for `lib/` modules, with explicit `require` only for critical boot-time modules.

## Boot Sequence

`lib/source_monitor.rb` loads in this order:

1. **Optional gems** (rescue LoadError): `solid_queue`, `solid_cable`, `turbo-rails`, `ransack`
2. **Table name prefix** setup via `redefine_method`
3. **Explicit requires** (11 files -- must load at boot):
   - `version`, `engine`, `configuration`, `model_extensions`
   - `events`, `instrumentation`, `metrics`
   - `health`, `realtime`, `feedjira_extensions`
4. **Autoload declarations** (71 modules) organized by namespace

## Engine Configuration

`SourceMonitor::Engine` (`lib/source_monitor/engine.rb`):
- `isolate_namespace SourceMonitor`
- Table name prefix from `config.models.table_name_prefix`
- Initializers: assets, metrics subscribers, dashboard streams, jobs/Solid Queue setup

## Module Tree

```
SourceMonitor (top-level)
|-- HTTP                    # Faraday HTTP client factory
|-- Scheduler               # Fetch scheduling coordinator
|-- Assets                  # Asset path helpers
|
|-- Analytics/              # Dashboard analytics queries
|   |-- SourceFetchIntervalDistribution
|   |-- SourceActivityRates
|   |-- SourcesIndexMetrics
|
|-- Dashboard/              # Dashboard UI support
|   |-- QuickAction, QuickActionsPresenter
|   |-- RecentActivity, RecentActivityPresenter
|   |-- Queries, TurboBroadcaster
|   |-- UpcomingFetchSchedule
|
|-- Fetching/               # Feed fetch pipeline
|   |-- FeedFetcher          # Main orchestrator
|   |   |-- AdaptiveInterval # Interval calculation
|   |   |-- SourceUpdater    # Source state updates
|   |   |-- EntryProcessor   # Entry iteration + item creation
|   |-- FetchRunner          # Job-level fetch coordinator
|   |-- RetryPolicy          # Retry/circuit-breaker decisions
|   |-- StalledFetchReconciler
|   |-- AdvisoryLock         # PG advisory locks
|   |-- FetchError (+ subclasses)
|
|-- Items/                  # Item management
|   |-- ItemCreator          # Create/update items from entries
|   |   |-- EntryParser      # Parse feed entries to attributes
|   |   |-- ContentExtractor # Process content through readability
|   |-- RetentionPruner      # Age/count-based item cleanup
|   |-- RetentionStrategies/ # Destroy vs SoftDelete
|
|-- ImportSessions/         # OPML import support
|   |-- EntryNormalizer
|   |-- HealthCheckBroadcaster
|
|-- Jobs/                   # Job infrastructure
|   |-- CleanupOptions
|   |-- Visibility           # Queue visibility setup
|   |-- SolidQueueMetrics
|   |-- FetchFailureSubscriber
|
|-- Logs/                   # Unified log system
|   |-- EntrySync            # Sync log records to LogEntry
|   |-- FilterSet, Query, TablePresenter
|
|-- Models/                 # Model concerns
|   |-- Sanitizable          # String/hash sanitization
|   |-- UrlNormalizable      # URL normalization
|
|-- Scrapers/               # Content scraping adapters
|   |-- Base                 # Scraper interface
|   |-- Readability          # Default readability adapter
|   |-- Fetchers/HttpFetcher
|   |-- Parsers/ReadabilityParser
|
|-- Scraping/               # Scraping orchestration
|   |-- Enqueuer, Scheduler
|   |-- ItemScraper (+ AdapterResolver, Persistence)
|   |-- BulkSourceScraper, BulkResultPresenter
|   |-- State
|
|-- Configuration/          # Configuration DSL (12 settings files)
|   |-- HTTPSettings, FetchingSettings, HealthSettings
|   |-- ScrapingSettings, RealtimeSettings, RetentionSettings
|   |-- AuthenticationSettings, ScraperRegistry
|   |-- Events, ValidationDefinition
|   |-- ModelDefinition, Models
|
|-- Security/               # Security layer
|   |-- ParameterSanitizer
|   |-- Authentication
|
|-- Setup/                  # Install/setup wizard
|   |-- CLI, Workflow, Requirements
|   |-- Detectors, DependencyChecker
|   |-- GemfileEditor, BundleInstaller, NodeInstaller
|   |-- InstallGenerator, MigrationInstaller, InitializerPatcher
|   |-- Verification/ (Result, Runner, Printer, etc.)
|
|-- Pagination/Paginator
|-- Release/ (Changelog, Runner)
|-- Sources/ (Params, TurboStreamPresenter)
|-- TurboStreams/StreamResponder
```

## Key Architectural Patterns

### 1. Configuration DSL

The `Configuration` class composes 12 settings objects:

```ruby
SourceMonitor.configure do |config|
  config.http.timeout = 30
  config.fetching.min_interval_minutes = 5
  config.health.auto_pause_threshold = 0.3
  config.retention.strategy = :soft_delete
  config.scraping.concurrency = 3
  config.models.table_name_prefix = "sm_"
end
```

Each settings class is a standalone PORO with defaults. Configuration is resettable via `reset_configuration!`.

### 2. ModelExtensions Registry

Models register themselves at class load time:
```ruby
SourceMonitor::ModelExtensions.register(self, :source)
```

This enables:
- Dynamic table name prefixing
- Host-app concern injection
- Host-app validation injection
- Full reload on config change

### 3. Event System

Three lifecycle events dispatched through `SourceMonitor::Events`:

| Event | Fired When | Payload |
|-------|-----------|---------|
| `after_item_created` | New item saved | ItemCreatedEvent |
| `after_item_scraped` | Scrape completed | ItemScrapedEvent |
| `after_fetch_completed` | Fetch finished | FetchCompletedEvent |

Plus `item_processors` -- callbacks run for every item (created or updated).

Events are registered via `config.events` and dispatched with error isolation per handler.

### 4. Instrumentation (ActiveSupport::Notifications)

| Event | Purpose |
|-------|---------|
| `source_monitor.fetch.start` | Fetch beginning |
| `source_monitor.fetch.finish` | Fetch completed |
| `source_monitor.items.duplicate` | Duplicate item detected |
| `source_monitor.items.retention` | Retention pruning |

`Metrics` module subscribes to these and maintains counters/gauges.

### 5. Pipeline Architecture

**Fetch Pipeline:**
```
FetchRunner
  -> AdvisoryLock (PG lock per source)
    -> FeedFetcher.call
      -> HTTP request (Faraday)
      -> Parse feed (Feedjira)
      -> EntryProcessor.process_feed_entries
        -> ItemCreator.call (per entry)
          -> EntryParser.parse
          -> ContentExtractor.process_feed_content
        -> Events.run_item_processors
        -> Events.after_item_created
      -> SourceUpdater.update_source_for_success
        -> AdaptiveInterval.apply_adaptive_interval!
      -> SourceUpdater.create_fetch_log
      -> Events.after_fetch_completed
    -> Completion handlers (retention, follow-up scraping)
```

**Scrape Pipeline:**
```
Scraping::Enqueuer
  -> ItemScraper
    -> AdapterResolver (select scraper)
    -> Scrapers::Base subclass
      -> Fetchers::HttpFetcher
      -> Parsers::ReadabilityParser
    -> Persistence (save to ItemContent)
    -> Events.after_item_scraped
```

### 6. Health Monitoring

Health module hooks into `after_fetch_completed`:
- `SourceHealthMonitor` -- calculates rolling success rate
- `SourceHealthCheck` -- HTTP health probe
- Auto-pause sources below threshold
- `SourceHealthReset` -- manual health reset

## References

- [Module Map](reference/module-map.md) -- Full module tree with responsibilities
- [Extraction Patterns](reference/extraction-patterns.md) -- Refactoring patterns from Phase 3/4
- Main entry: `lib/source_monitor.rb`
- Engine: `lib/source_monitor/engine.rb`
- Configuration: `lib/source_monitor/configuration.rb` + `lib/source_monitor/configuration/*.rb`
