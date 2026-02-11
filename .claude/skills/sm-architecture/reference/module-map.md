# SourceMonitor Module Map

Complete module tree with each module's responsibility.

## Top-Level Modules (Explicit Require)

| Module | File | Responsibility |
|--------|------|----------------|
| `SourceMonitor` | `lib/source_monitor.rb` | Namespace root, configure/reset API, autoload declarations |
| `Engine` | `lib/source_monitor/engine.rb` | Rails engine setup, isolate_namespace, initializers |
| `Configuration` | `lib/source_monitor/configuration.rb` | Central config object, composes 12 settings objects |
| `ModelExtensions` | `lib/source_monitor/model_extensions.rb` | Dynamic table names, concern/validation injection |
| `Events` | `lib/source_monitor/events.rb` | Lifecycle event dispatch (item created, scraped, fetch completed) |
| `Instrumentation` | `lib/source_monitor/instrumentation.rb` | ActiveSupport::Notifications wrapper |
| `Metrics` | `lib/source_monitor/metrics.rb` | Counter/gauge tracking, notification subscribers |
| `Health` | `lib/source_monitor/health.rb` | Health monitoring setup, fetch callback registration |
| `Realtime` | `lib/source_monitor/realtime.rb` | ActionCable/Turbo Streams adapter and broadcaster setup |
| `FeedJiraExtensions` | `lib/source_monitor/feedjira_extensions.rb` | Feedjira monkey-patches/extensions |

## Autoloaded Modules

### SourceMonitor (Root Level)

| Module | File | Responsibility |
|--------|------|----------------|
| `HTTP` | `http.rb` | Faraday client factory with configurable timeouts, user-agent, headers |
| `Scheduler` | `scheduler.rb` | Coordinates scheduled fetch jobs |
| `Assets` | `assets.rb` | Asset path resolution helpers |

### Analytics

| Module | File | Responsibility |
|--------|------|----------------|
| `SourceFetchIntervalDistribution` | `analytics/source_fetch_interval_distribution.rb` | Distribution stats for fetch intervals |
| `SourceActivityRates` | `analytics/source_activity_rates.rb` | Item creation rates per source |
| `SourcesIndexMetrics` | `analytics/sources_index_metrics.rb` | Aggregate metrics for sources index |

### Dashboard

| Module | File | Responsibility |
|--------|------|----------------|
| `QuickAction` | `dashboard/quick_action.rb` | Quick action data object |
| `QuickActionsPresenter` | `dashboard/quick_actions_presenter.rb` | Format quick actions for view |
| `RecentActivity` | `dashboard/recent_activity.rb` | Recent activity query |
| `RecentActivityPresenter` | `dashboard/recent_activity_presenter.rb` | Format activity for view |
| `Queries` | `dashboard/queries.rb` | Dashboard aggregate queries |
| `TurboBroadcaster` | `dashboard/turbo_broadcaster.rb` | Broadcast dashboard updates |
| `UpcomingFetchSchedule` | `dashboard/upcoming_fetch_schedule.rb` | Next-fetch schedule display |

### Fetching (Feed Fetch Pipeline)

| Module | File | Responsibility |
|--------|------|----------------|
| `FeedFetcher` | `fetching/feed_fetcher.rb` | Main fetch orchestrator: request, parse, process entries, update source |
| `FeedFetcher::AdaptiveInterval` | `fetching/feed_fetcher/adaptive_interval.rb` | Compute next fetch interval based on content changes |
| `FeedFetcher::SourceUpdater` | `fetching/feed_fetcher/source_updater.rb` | Update source record after fetch (success/failure/not-modified) |
| `FeedFetcher::EntryProcessor` | `fetching/feed_fetcher/entry_processor.rb` | Iterate feed entries, call ItemCreator, fire events |
| `FetchRunner` | `fetching/fetch_runner.rb` | Job-level coordinator: acquire lock, run FeedFetcher, handle completion |
| `RetryPolicy` | `fetching/retry_policy.rb` | Retry/circuit-breaker decision logic |
| `StalledFetchReconciler` | `fetching/stalled_fetch_reconciler.rb` | Reset sources stuck in "fetching" status |
| `AdvisoryLock` | `fetching/advisory_lock.rb` | PostgreSQL advisory lock wrapper |
| `FetchError` | `fetching/fetch_error.rb` | Error hierarchy (TimeoutError, ConnectionError, HTTPError, ParsingError, UnexpectedResponseError) |

### Items

| Module | File | Responsibility |
|--------|------|----------------|
| `ItemCreator` | `items/item_creator.rb` | Create or update Item from feed entry |
| `ItemCreator::EntryParser` | `items/item_creator/entry_parser.rb` | Parse Feedjira entry into attribute hash |
| `ItemCreator::ContentExtractor` | `items/item_creator/content_extractor.rb` | Process content through readability parser |
| `RetentionPruner` | `items/retention_pruner.rb` | Prune items by age/count per source |
| `RetentionStrategies` | `items/retention_strategies.rb` | Strategy pattern for retention |
| `RetentionStrategies::Destroy` | `items/retention_strategies/destroy.rb` | Hard-delete retention strategy |
| `RetentionStrategies::SoftDelete` | `items/retention_strategies/soft_delete.rb` | Soft-delete retention strategy |

### ImportSessions

| Module | File | Responsibility |
|--------|------|----------------|
| `EntryNormalizer` | `import_sessions/entry_normalizer.rb` | Normalize OPML entries to standard format |
| `HealthCheckBroadcaster` | `import_sessions/health_check_broadcaster.rb` | Broadcast health check progress via Turbo Streams |

### Jobs

| Module | File | Responsibility |
|--------|------|----------------|
| `CleanupOptions` | `jobs/cleanup_options.rb` | Options for job cleanup tasks |
| `Visibility` | `jobs/visibility.rb` | Configure queue visibility for Solid Queue |
| `SolidQueueMetrics` | `jobs/solid_queue_metrics.rb` | Extract metrics from Solid Queue tables |
| `FetchFailureSubscriber` | `jobs/fetch_failure_subscriber.rb` | ActiveJob error subscriber for fetch failures |

### Logs

| Module | File | Responsibility |
|--------|------|----------------|
| `EntrySync` | `logs/entry_sync.rb` | Sync FetchLog/ScrapeLog/HealthCheckLog to unified LogEntry |
| `FilterSet` | `logs/filter_set.rb` | Log filtering parameters |
| `Query` | `logs/query.rb` | Log query builder |
| `TablePresenter` | `logs/table_presenter.rb` | Format log entries for table display |

### Models (Shared Concerns)

| Module | File | Responsibility |
|--------|------|----------------|
| `Sanitizable` | `models/sanitizable.rb` | `sanitizes_string_attributes`, `sanitizes_hash_attributes` class methods |
| `UrlNormalizable` | `models/url_normalizable.rb` | `normalizes_urls`, `validates_url_format` class methods |

### Scrapers (Scraper Adapters)

| Module | File | Responsibility |
|--------|------|----------------|
| `Base` | `scrapers/base.rb` | Abstract scraper interface |
| `Readability` | `scrapers/readability.rb` | Default readability-based scraper |
| `Fetchers::HttpFetcher` | `scrapers/fetchers/http_fetcher.rb` | HTTP content fetcher for scrapers |
| `Parsers::ReadabilityParser` | `scrapers/parsers/readability_parser.rb` | Parse HTML to readable content |

### Scraping (Scraping Orchestration)

| Module | File | Responsibility |
|--------|------|----------------|
| `Enqueuer` | `scraping/enqueuer.rb` | Queue scrape jobs for items |
| `Scheduler` | `scraping/scheduler.rb` | Schedule scraping across sources |
| `ItemScraper` | `scraping/item_scraper.rb` | Scrape a single item |
| `ItemScraper::AdapterResolver` | `scraping/item_scraper/adapter_resolver.rb` | Select scraper adapter for a source |
| `ItemScraper::Persistence` | `scraping/item_scraper/persistence.rb` | Save scrape results to ItemContent |
| `BulkSourceScraper` | `scraping/bulk_source_scraper.rb` | Scrape all pending items for a source |
| `BulkResultPresenter` | `scraping/bulk_result_presenter.rb` | Format bulk scrape results |
| `State` | `scraping/state.rb` | Track scraping state per source |

### Configuration (12 Settings Files)

| Module | File | Responsibility |
|--------|------|----------------|
| `HTTPSettings` | `configuration/http_settings.rb` | HTTP timeouts, user-agent, proxy |
| `FetchingSettings` | `configuration/fetching_settings.rb` | Adaptive interval params, retry config |
| `HealthSettings` | `configuration/health_settings.rb` | Health check thresholds, auto-pause config |
| `ScrapingSettings` | `configuration/scraping_settings.rb` | Scraping concurrency, timeouts |
| `RealtimeSettings` | `configuration/realtime_settings.rb` | ActionCable/Turbo Streams config |
| `RetentionSettings` | `configuration/retention_settings.rb` | Item retention strategy, defaults |
| `AuthenticationSettings` | `configuration/authentication_settings.rb` | Auth callbacks for host app |
| `ScraperRegistry` | `configuration/scraper_registry.rb` | Register custom scraper adapters |
| `Events` | `configuration/events.rb` | Event callback storage |
| `ValidationDefinition` | `configuration/validation_definition.rb` | Host-app validation definitions |
| `ModelDefinition` | `configuration/model_definition.rb` | Per-model extension definitions |
| `Models` | `configuration/models.rb` | Model registry and table prefix config |

### Health

| Module | File | Responsibility |
|--------|------|----------------|
| `SourceHealthMonitor` | `health/source_health_monitor.rb` | Calculate rolling success rate, update health_status |
| `SourceHealthCheck` | `health/source_health_check.rb` | Perform HTTP health check on a source |
| `SourceHealthReset` | `health/source_health_reset.rb` | Reset health state for a source |
| `ImportSourceHealthCheck` | `health/import_source_health_check.rb` | Health check for import session sources |

### Security

| Module | File | Responsibility |
|--------|------|----------------|
| `ParameterSanitizer` | `security/parameter_sanitizer.rb` | Sanitize controller parameters |
| `Authentication` | `security/authentication.rb` | Authentication helper callbacks |

### Setup (Install Wizard)

| Module | File | Responsibility |
|--------|------|----------------|
| `CLI` | `setup/cli.rb` | Command-line interface for setup |
| `Workflow` | `setup/workflow.rb` | Step-by-step setup orchestration |
| `Requirements` | `setup/requirements.rb` | System requirements checking |
| `Detectors` | `setup/detectors.rb` | Detect existing config/gems |
| `DependencyChecker` | `setup/dependency_checker.rb` | Check gem dependencies |
| `GemfileEditor` | `setup/gemfile_editor.rb` | Edit host app Gemfile |
| `BundleInstaller` | `setup/bundle_installer.rb` | Run bundle install |
| `NodeInstaller` | `setup/node_installer.rb` | Install Node.js dependencies |
| `InstallGenerator` | `setup/install_generator.rb` | Rails generator for install |
| `MigrationInstaller` | `setup/migration_installer.rb` | Copy and run migrations |
| `InitializerPatcher` | `setup/initializer_patcher.rb` | Patch host app initializer |
| `Verification::Result` | `setup/verification/result.rb` | Verification result + summary |
| `Verification::Runner` | `setup/verification/runner.rb` | Run all verification checks |
| `Verification::Printer` | `setup/verification/printer.rb` | Print verification results |
| `Verification::SolidQueueVerifier` | `setup/verification/solid_queue_verifier.rb` | Verify Solid Queue setup |
| `Verification::ActionCableVerifier` | `setup/verification/action_cable_verifier.rb` | Verify Action Cable setup |
| `Verification::TelemetryLogger` | `setup/verification/telemetry_logger.rb` | Log setup telemetry |

### Other

| Module | File | Responsibility |
|--------|------|----------------|
| `Pagination::Paginator` | `pagination/paginator.rb` | Offset-based pagination helper |
| `Release::Changelog` | `release/changelog.rb` | Generate changelog from git history |
| `Release::Runner` | `release/runner.rb` | Coordinate gem release process |
| `Sources::Params` | `sources/params.rb` | Strong parameter definitions |
| `Sources::TurboStreamPresenter` | `sources/turbo_stream_presenter.rb` | Source Turbo Stream formatting |
| `TurboStreams::StreamResponder` | `turbo_streams/stream_responder.rb` | Turbo Stream response builder |
