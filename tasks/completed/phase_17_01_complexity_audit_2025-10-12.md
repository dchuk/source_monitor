# Phase 17.01 Complexity Audit (2025-10-12)

## Component Inventory

- **Controllers (7)**: `SourceMonitor::ApplicationController`, `DashboardController`, `SourcesController`, `ItemsController`, `FetchLogsController`, `ScrapeLogsController`, `HealthController`.
- **Models (6)**: `SourceMonitor::ApplicationRecord`, `Source`, `Item`, `ItemContent`, `FetchLog`, `ScrapeLog`.
- **Jobs (6)**: `ApplicationJob`, `FetchFeedJob`, `ScrapeItemJob`, `ScheduleFetchesJob`, `ItemCleanupJob`, `LogCleanupJob`.
- **Service/Support Modules (34)**: Analytics (`Analytics::SourceFetchIntervalDistribution`, `Analytics::SourceActivityRates`), Dashboard (`Dashboard::Queries`, `Dashboard::TurboBroadcaster`, `Dashboard::UpcomingFetchSchedule`), Fetching (`Fetching::FeedFetcher`, `Fetching::FetchRunner`, `Fetching::FetchError`, `Fetching::RetryPolicy`), HTTP (`HTTP`), Instrumentation (`Instrumentation`, `Events`, `Metrics`), Items (`Items::ItemCreator`, `Items::RetentionPruner`), Jobs support (`Jobs::SolidQueueMetrics`, `Jobs::Visibility`), Realtime (`Realtime`, `Realtime::Adapter`, `Realtime::Broadcaster`), Scheduler (`Scheduler`, `Scraping::Scheduler`), Scraping (`Scraping::Enqueuer`, `Scraping::ItemScraper`, `Scrapers::Base`, `Scrapers::Readability`, `Scrapers::Fetchers::HttpFetcher`, `Scrapers::Parsers::ReadabilityParser`), Security (`Security::Authentication`, `Security::ParameterSanitizer`), Configuration (`Configuration`, `ModelExtensions`, `feedjira` extensions, `version`).
- **View Components**: none defined under `app/components`.
- **Front-End Assets**: Stimulus bootstrapper `app/assets/javascripts/source_monitor/application.js`, controllers (`controllers/notification_controller.js`, `controllers/async_submit_controller.js`, `controllers/dropdown_controller.js`), transition shim `dropdown_transition_shim.js`, sprockets manifest `application.js`, Tailwind sources `app/assets/tailwind/application.css`, compiled Tailwind bundle `app/assets/builds/tailwind.css` (~1.4k lines), stylesheet manifest `app/assets/stylesheets/source_monitor/application.css`, Turbo-aware notification partials under `app/views/source_monitor/shared/` (not exhaustively listed).

## Controller Review (17.01.02)

- `SourcesController#index` mixes search sanitization, analytics aggregation, and bucket math, making the action broader than RESTful list concerns. Extracting the distribution helpers (`extract_fetch_interval_filter`, `distribution_sources_scope`, `find_matching_bucket`) into a presenter or query object would clarify the controller's responsibility (`app/controllers/source_monitor/sources_controller.rb:11-199`).
- Both `SourcesController` and `ItemsController` duplicate an identical `sanitized_search_params` implementation; moving it into a concern would reduce coupling to parameter structure (`app/controllers/source_monitor/sources_controller.rb:172-194`, `app/controllers/source_monitor/items_controller.rb:120-140`).
- Manual pagination in `ItemsController#index` reimplements offset/limit logic and page bounds; adopting a pagination helper like Pagy would cut duplication and guard against off-by-one errors (`app/controllers/source_monitor/items_controller.rb:21-29`).
- Non-RESTful actions (`fetch`/`retry` on Sources, `scrape` on Items) are correctly routed but include complex Turbo Stream responses inline; extracting to responder objects would improve reusability and testability (`app/controllers/source_monitor/sources_controller.rb:65-168`, `app/controllers/source_monitor/items_controller.rb:38-83`).
- `FetchLogsController` and `ScrapeLogsController` share similar filtering logic but diverge in integer parsing; consider consolidating to a shared concern to keep future filter changes in one place (`app/controllers/source_monitor/fetch_logs_controller.rb:5-23`, `app/controllers/source_monitor/scrape_logs_controller.rb:5-45`).

## Model and Service Review (17.01.03)

- `SourceMonitor::Source` handles normalization, sanitization, health defaults, and validation in a single model class. The sanitization callbacks (`sanitize_user_inputs`) could move to a concern shared with other models to avoid repeating security rules elsewhere (`app/models/source_monitor/source.rb:47-151`).
- `SourceMonitor::Item` embeds URL normalization and soft-delete logic. Extracting the normalization routine (`normalize_urls`) to a reusable helper would support other URL-bearing models (`app/models/source_monitor/item.rb:52-133`).
- `Fetching::FetchRunner` coordinates locking, fetch execution, retention pruning, retry scheduling, and scrape enqueueing. Splitting concurrency/locking into a collaborator would keep the runner focused on orchestration (`lib/source_monitor/fetching/fetch_runner.rb:39-186`).
- `Scraping::ItemScraper` owns adapter resolution, persistence, logging, and error translation in one class; consider splitting adapter lookup and persistence so new adapters can be added without touching the transaction workflow (`lib/source_monitor/scraping/item_scraper.rb:28-200`).
- `Items::RetentionPruner` mixes strategy selection with batch execution and counter maintenance; moving strategy-specific behavior into separate classes would make the soft-delete vs destroy paths easier to evolve (`lib/source_monitor/items/retention_pruner.rb:21-162`).
- `Dashboard::Queries` executes multiple direct ActiveRecord calls every page load; caching or background precomputation for expensive counts (e.g., `FetchLog` and `ScrapeLog` limits) could improve dashboard responsiveness (`lib/source_monitor/dashboard/queries.rb:9-87`).

## Jobs, Workers, and Scheduling (17.01.04)

- `FetchFeedJob` re-raises all errors except concurrency conflicts, delegating retries to ActiveJob defaults. Considering explicit retry/backoff for transient failures would align with Solid Queue best practices (`app/jobs/source_monitor/fetch_feed_job.rb:5-19`).
- `ScrapeItemJob` performs direct `update_columns` writes inside locks; wrapping these state changes in small service objects (or reusing `Scraping::Enqueuer` helpers) would reduce raw SQL usage and prevent silent attribute drift (`app/jobs/source_monitor/scrape_item_job.rb:21-56`).
- Cleanup jobs (`ItemCleanupJob`, `LogCleanupJob`) repeat option normalization logic; a shared base utility could centralize casting rules for command-line invocations (`app/jobs/source_monitor/item_cleanup_job.rb:12-74`, `app/jobs/source_monitor/log_cleanup_job.rb:14-78`).
- `Scheduler.run` only enqueues fetches; adding observability (e.g., instrumentation events around locked IDs) would help diagnose scheduling gaps (`lib/source_monitor/scheduler.rb:7-55`).
- Recurring schedule references in `config/recurring.yml` rely on Solid Queue CLI defaults; documenting these in `SourceMonitor.configure` and ensuring Mission Control checks respect them would reduce drift across host apps.

## Front-End Asset Review (17.01.05)

- Stimulus controllers register themselves on the global `window` object and expect external UMD bundles (`app/assets/javascripts/source_monitor/application.js:1-32`, `app/assets/javascripts/source_monitor/controllers/notification_controller.js:1-55`). Migrating to Importmap or ESbuild modules would eliminate global leakage and simplify testing.
- `dropdown_controller.js` assumes a global `StimulusDropdown` shim; when the dependency is absent, dropdowns silently fail. Guarding this with feature detection and graceful degradation (e.g., fallback to CSS-only menus) would improve resilience (`app/assets/javascripts/source_monitor/controllers/dropdown_controller.js:1-14`).
- The transition shim provides minimal show/hide toggling and bypasses Tailwind’s transition helpers; aligning it with the stimulus-use-transition API would avoid divergence from upstream updates (`app/assets/javascripts/source_monitor/dropdown_transition_shim.js:1-25`).
- A compiled Tailwind bundle (`app/assets/builds/tailwind.css`) lives in source control; documenting the build step and ensuring the bundle is regenerated during releases will prevent stale utility classes.
- No dedicated asset linting or bundler checks run in CI; adding `yarn lint` or equivalent (once build tooling is selected) would catch drift early.

## Metrics & Hotspots (17.01.06)

- `bundle exec rubocop --format offenses` reports **366 offenses across 44 files**, overwhelmingly `Layout/SpaceInsideArrayLiteralBrackets` (352 autocorrectable). Cleaning whitespace rules and enabling CI enforcement will quickly improve signal-to-noise.
- `bundle exec brakeman` could not run because the gem is not in the bundle; adding it to the development group will enable baseline security scanning.
- SimpleCov is not configured (`test/test_helper.rb` lacks coverage hooks), so historical coverage trends are unavailable; enabling coverage reports will support future regressions analysis.
- Hotspot summary:
  - Controllers: duplicated sanitization helper and complex inline Turbo responses (`SourcesController#index`, `ItemsController#scrape`).
  - Services: `Fetching::FetchRunner` and `Scraping::ItemScraper` concentrate orchestration, logging, and persistence logic in single classes, making them prime candidates for refactoring.
  - Jobs: Cleanup jobs’ duplicated option parsing invites inconsistencies when adding CLI flags.
  - Front-end: reliance on global Stimulus objects without build-time enforcement increases risk of runtime errors when assets load out of order.

## Recommended Next Steps

1. Extract shared request-sanitization and pagination helpers to reduce duplication in controllers.
2. Break down `FetchRunner` and `ItemScraper` into smaller collaborators (e.g., concurrency guard, adapter resolver, persistence handler) to improve testability.
3. Add Rubocop autocorrect (spacing rules) and wire Rubocop/Brakeman into CI to maintain quality gates.
4. Decide on an asset pipeline (Importmap vs ESBuild) and refactor Stimulus controllers out of the global namespace, documenting required UMD shims until migration completes.
5. Enable SimpleCov and capture baseline coverage for future phases, ensuring retention and scraping flows stay covered.
