# Changelog

All notable changes to this project are documented below. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to Semantic Versioning.

## Release Checklist

1. `rbenv exec bundle exec rails test`
2. `rbenv exec bundle exec rubocop`
3. `rbenv exec bundle exec rake app:source_monitor:assets:verify`
4. `rbenv exec bundle exec gem build source_monitor.gemspec`
5. Update release notes in this file and tag the release (`git tag vX.Y.Z`)
6. Push tags and publish the gem (`rbenv exec gem push pkg/source_monitor-X.Y.Z.gem`)

## [Unreleased]

- No unreleased changes yet.

## [0.10.2] - 2026-02-26

### Fixed

- **Association cache pollution in ItemCreator no longer causes cascading validation failures.** When `source.items.new` was used to build new items, failed saves (e.g., invalid URLs) left unsaved records in the association cache. Subsequent `source.update!` calls triggered Rails' has_many auto-save on the invalid cached items, causing `RecordInvalid: Items is invalid` errors. Fixed by constructing items via `Item.new(source_id:)` to bypass the association cache, and by switching FetchRunner's status updates to `update_columns` for defense-in-depth.

## [0.10.1] - 2026-02-25

### Fixed

- **Backfill word counts rake task optimized for large datasets.** Replaced row-by-row saves with `insert_all` (Phase 1) and `upsert_all` (Phase 2), eliminating N+1 queries and `touch` cascades. ~1000x query reduction for large datasets.
- **ActiveRecord::Deadlocked no longer silently swallowed in jobs.** `DownloadContentImagesJob` and `FaviconFetchJob` previously caught all `StandardError` including database deadlocks, causing Active Storage operations to fail silently during concurrent access. Deadlocks now propagate so the job framework can retry.
- **Thread-safe configuration access.** `SourceMonitor.configure`, `.config`, and `.reset_configuration!` now synchronize via `Monitor` to prevent race conditions during parallel test execution.
- **Flaky seed-dependent test failures resolved.** Added `clean_source_monitor_tables!` to `StaggerFetchTimesTaskTest` to prevent cross-test database contamination from `setup_once` records leaking via test-prof with thread-based parallelism.
- **Suppressed spurious DeprecationRegistry warning in test output.** The "http.timeout already exists" warning from the deprecation skip-path test no longer leaks to stderr.

## [0.10.0] - 2026-02-24

### Added

- **Maintenance queue for non-fetch jobs.** New third queue (`source_monitor_maintenance`) separates non-time-sensitive jobs from the fetch pipeline. Health checks, cleanup, favicon fetching, image downloading, and OPML import jobs now run on the maintenance queue, keeping the fetch queue dedicated to `FetchFeedJob` and `ScheduleFetchesJob`. Configure via `config.maintenance_queue_name` and `config.maintenance_queue_concurrency`.
- **Configurable scheduler batch size.** `config.fetching.scheduler_batch_size` (default `25`, was hardcoded at `100`) controls how many sources are picked up per scheduler run. Optimized for 1-CPU/2GB servers.
- **Configurable stale fetch timeout.** `config.fetching.stale_timeout_minutes` (default `5`, was hardcoded at `10`) controls how long a source can remain in "fetching" status before the stalled fetch reconciler resets it.
- **Stagger fetch times rake task.** `source_monitor:maintenance:stagger_fetch_times` distributes all currently-due sources across a configurable time window (`WINDOW_MINUTES` env var, default 10 minutes), breaking thundering herd patterns after deploys, queue stalls, or large OPML imports.

### Fixed

- **Fetch pipeline error handling safety net.** DB update failures in `update_source_state!` now propagate instead of being silently swallowed. Broadcast failures are still rescued (non-critical). An `ensure` block in `FetchRunner#run` guarantees fetch_status resets from "fetching" to "failed" on any unexpected exit path. `FollowUpHandler` now rescues per-item scrape enqueue failures so one bad item doesn't block remaining enqueues.
- **Fixed-interval sources now get scheduling jitter.** Sources using fixed fetch intervals (not adaptive) now receive ±10% jitter on `next_fetch_at`, preventing thundering herd effects when many sources share the same interval.
- **ScheduleFetchesJob uses configured batch size.** The job's fallback limit now reads `config.fetching.scheduler_batch_size` (25) instead of the legacy `DEFAULT_BATCH_SIZE` constant (100).

### Changed

- Default scheduler batch size reduced from 100 to 25 (configurable via `config.fetching.scheduler_batch_size`).
- Default stale fetch timeout reduced from 10 to 5 minutes (configurable via `config.fetching.stale_timeout_minutes`).
- 7 jobs moved from fetch queue to maintenance queue: `SourceHealthCheckJob`, `ImportSessionHealthCheckJob`, `ImportOpmlJob`, `LogCleanupJob`, `ItemCleanupJob`, `FaviconFetchJob`, `DownloadContentImagesJob`.

### Testing

- 1,214 tests, 3,765 assertions, 0 failures.
- RuboCop: 0 offenses (424 files).
- Brakeman: 0 warnings.

## [0.9.1] - 2026-02-22

### Fixed

- **Feed word counts now always computed.** Items fetched from feeds but never scraped now get an `ItemContent` record with `feed_word_count` automatically. Previously, only scraped items had `ItemContent`, so the `backfill_word_counts` rake task found nothing for feed-only items.
- **Backfill task creates missing ItemContent records.** `source_monitor:backfill_word_counts` now has a two-phase approach: first creates `ItemContent` for items with feed content but no record, then recomputes all word counts.
- **ItemContent preserved when item has feed content.** Clearing scraped fields no longer destroys the `ItemContent` record if the item still has feed content (which provides `feed_word_count`).

## [0.9.0] - 2026-02-22

### Added

- **Sources pagination and filtering.** Sources index now paginates (25 per page, configurable) with Previous/Next controls. Dropdown filters for Status, Health, Format, and Scraper Adapter auto-submit on change. Active filters shown as dismissible badges. Text search and dropdown filters compose as intersection and persist across pagination.
- **Per-source scrape rate limiting.** New `min_scrape_interval` column on sources allows time-based throttling between scrapes. Global default (1.0s) configurable via `config.scraping.min_scrape_interval`. Per-source overrides via the column value. ScrapeItemJob and Enqueuer check last scrape time from `scrape_logs` and re-enqueue with delay when rate-limited.
- **Word count metrics.** New `feed_word_count` and `scraped_word_count` columns on `item_contents`. Feed content is HTML-stripped before counting; scraped content counted as-is (readability-cleaned). Separate "Avg Feed Words" and "Avg Scraped Words" columns on sources index. Separate "Feed Words" and "Scraped Words" columns on items index and source detail items table. Backfill rake task: `source_monitor:backfill_word_counts`.

### Fixed

- Show `created_at` fallback when `published_at` is nil in items table.
- Handle source destroy failures with proper error responses instead of silent failures.
- UI fixes: navigation warning indicator positioning, toast container placement, dashboard table alignment.
- N+1 query fix: source detail items table now uses `includes(:item_content)`.

### Testing

- 1,175 tests, 3,683 assertions, 0 failures.
- RuboCop: 0 offenses (423 files).

## [0.8.1] - 2026-02-21

### Fixed

- **OPML import now imports all selected feeds across pages.** Previously, only the 25 feeds visible on the current preview page were imported. Pagination links inside the preview form triggered full-page navigation (bypassing Turbo Frames), which caused a "leave site?" warning and lost selections from other pages. Hidden fields now preserve selections across pages, and pagination uses Turbo Frame navigation.

### Changed

- Removed deprecated `rails/tasks/statistics.rake` from Rakefile (Rails 8.2 compatibility).

## [0.8.0] - 2026-02-21

### Added

- **Automatic source favicons.** Sources now display favicons next to their names in list and detail views. Favicons are fetched automatically via background job on source creation and successful feed fetches using a multi-strategy cascade: `/favicon.ico` direct fetch, HTML `<link>` tag parsing (preferring largest available), and Google Favicon API fallback. Requires Active Storage in the host app.
  - New configuration section: `config.favicons` with `enabled` (default: `true`), `fetch_timeout` (5s), `max_download_size` (1MB), `retry_cooldown_days` (7), and `allowed_content_types` settings.
  - Colored initials placeholder shown when no favicon is available (consistent HSL color derived from source name).
  - Graceful degradation: host apps without Active Storage see placeholders only, no errors.
  - OPML imports also trigger favicon fetches for each imported source with a `website_url`.
  - Manual "Fetch Favicon" button on source detail pages; favicon fetch also triggered on 304 Not Modified responses when missing.
  - Redirect-following in favicon discoverer for domains that redirect (e.g., `reddit.com` -> `www.reddit.com`).
- **Toast notification stacking.** Bulk operations no longer flood the screen with overlapping toasts. At most 3 toasts are visible at a time; overflow is shown as a "+N more" badge that expands the full stack on click. "Clear all" button dismisses every toast at once.
  - Error-level toasts persist for 10 seconds (vs 5 seconds for info/success).
  - Hidden toasts promote into visible slots as earlier toasts auto-dismiss.
  - Container controller tracks DOM changes via MutationObserver and properly cleans up event listeners on disconnect.

### Changed

- **Browser-like default User-Agent.** Default HTTP User-Agent changed from `SourceMonitor/<version>` to `Mozilla/5.0 (compatible; SourceMonitor/<version>)` with full browser-like headers (Accept, Accept-Language, DNT, Referer from source `website_url`). This prevents bot-blocking by feed servers.
- **Smarter scrape rate limiting.** Default `max_in_flight_per_source` changed from `25` to `nil` (unlimited). The previous default unnecessarily throttled scraping for sources with many items. Set an explicit value in your initializer if you need per-source caps.
- **Health check triggers status re-evaluation.** A successful manual health check on a degraded (declining/critical/warning) source now triggers a feed fetch, allowing the health monitor to transition the source back to "improving" status instead of requiring the source to recover on its own schedule.

### Fixed

- Favicon discoverer properly follows HTTP redirects (e.g., `reddit.com` -> `www.reddit.com`).
- Favicon fetch uses `rails_blob_path` for correct routing within the engine context.
- Favicon display prefers PNG format (via Google Favicon API) over raw ICO for better browser compatibility.
- Gemspec excludes `.vbw-planning/` from gem package to reduce gem size.

### Testing

- 1,125 tests, 0 failures.
- RuboCop: 0 offenses.
- Brakeman: 0 warnings.

## [0.7.1] - 2026-02-18

### Changed

- **Test suite 60% faster (118s → 46s).** Disabled Faraday retry middleware in tests — WebMock-stubbed timeout errors triggered 4 retries with exponential backoff (7.5s of real sleep per test), consuming 73% of total runtime across 11 FeedFetcher tests.
- Split monolithic FeedFetcherTest (71 tests, 84.8s) into 6 concern-based test classes for better parallelization and maintainability.
- Switched default test parallelism from fork-based to thread-based, eliminating PG segfault on single-file runs.
- Reduced test log IO by setting test log level to `:warn` (was `:debug`, generating 95MB of output).
- Adopted `setup_once`/`before_all` in 5 DB-heavy analytics/dashboard test files.
- Added `test:fast` rake task to exclude integration and system tests during development.

### Fixed

- Suppressed spurious TestProf "before_all is not implemented for threads" warning by loading TestProf after `parallelize` call.

### Testing

- 1,033 tests, 3,302 assertions, 0 failures.
- RuboCop: 0 offenses.
- Brakeman: 0 warnings.

## [0.7.0] - 2026-02-18

### Fixed

- **False "updated" counts on unchanged feed items.** ItemCreator now checks for significant attribute changes before saving. Items with no real changes return a new `:unchanged` status instead of `:updated`, eliminating unnecessary database writes and misleading dashboard statistics.
- **Redundant entry processing on unchanged feeds.** When a feed's body SHA-256 signature matches the previous fetch, entry processing is now skipped entirely (like the existing 304 Not Modified path), avoiding unnecessary parsing, DB lookups, and saves.
- **Adaptive interval not backing off for stable feeds.** The `content_changed` signal for adaptive fetch scheduling now uses an item-level content hash (sorted entry IDs) instead of the raw XML body hash. This prevents cosmetic feed changes (e.g., `<lastBuildDate>` updates) from defeating interval backoff, allowing stable feeds to correctly increase their fetch interval.

### Testing

- 1,031 tests, 3,300 assertions, 0 failures.
- RuboCop: 0 offenses.
- Brakeman: 0 warnings.

## [0.6.0] - 2026-02-17

### Added

- AIA (Authority Information Access) certificate resolution for SSL failures. When feed fetching or scraping encounters `certificate verify failed` errors due to missing intermediate certificates, the engine now automatically fetches the missing intermediate via AIA URLs and retries the request. This fixes feeds hosted on servers with incomplete certificate chains (e.g., Medium/Netflix Tech Blog on AWS).
- `SourceMonitor::HTTP::AIAResolver` module with thread-safe hostname-keyed cache (1-hour TTL), SNI support, and DER/PEM certificate parsing.
- `cert_store:` parameter on `SourceMonitor::HTTP.client` for passing custom certificate stores.
- Brakeman ignore configuration (`config/brakeman.ignore`) for the intentional `VERIFY_NONE` in the AIA resolver's leaf certificate fetch.

### Testing

- 1,028 tests, 0 failures (up from 1,003 in 0.5.x).
- RuboCop: 0 offenses.
- Brakeman: 0 warnings (1 intentional ignore).

## [0.5.3] - 2026-02-16

### Fixed

- `PendingMigrationsVerifier` crash on Rails 8 (`undefined method 'migration_context'` on connection adapter). Now uses `connection_pool.migration_context` which is the Rails 8-compatible API.

## [0.5.2] - 2026-02-16

### Added

- `source_monitor:upgrade` rake task for host apps to run upgrades via `bin/rails source_monitor:upgrade` instead of the non-distributed `bin/source_monitor` CLI.

### Fixed

- PendingMigrationsVerifier false positive when host migrations have `.source_monitor` engine suffix (e.g., `create_source_monitor_sources.source_monitor.rb`).

## [0.5.1] - 2026-02-13

### Changed

- Bumped puma from 7.1.0 to 7.2.0 (17% faster HTTP parsing, `workers :auto`, GC-compactible C extension).
- Bumped solid_queue from 1.2.4 to 1.3.1 (async mode, bug fixes).
- Bumped turbo-rails from 2.0.20 to 2.0.23 (broadcast suppression fix, navigator clobbering fix).

## [0.5.0] - 2026-02-13

### Added

- `bin/source_monitor upgrade` command: detects version changes since last install, copies new migrations, re-runs the generator, runs verification, and reports what changed. Uses a `.source_monitor_version` marker file for version tracking.
- `PendingMigrationsVerifier` checks for unmigrated SourceMonitor tables in the verification suite, integrated into both `bin/source_monitor verify` and the upgrade flow.
- Configuration deprecation framework: engine developers can register deprecated config options with `DeprecationRegistry.register`. At boot time, stale options trigger `:warning` (renamed) or `:error` (removed) messages with actionable replacement paths.
- `sm-upgrade` AI skill guides agents through post-update workflows: CHANGELOG parsing, running the upgrade command, interpreting verification results, and handling deprecation warnings.
- `docs/upgrade.md` versioned upgrade guide with general steps, version-specific notes (0.1.x through 0.4.x), and troubleshooting.
- `sm-host-setup` skill cross-references the upgrade workflow.

### Testing

- 1,003 tests, 0 failures (up from 973 in 0.4.0).
- RuboCop: 397 files, 0 offenses.
- Brakeman: 0 warnings.

## [0.4.0] - 2026-02-12

### Added

- Install generator now auto-patches `Procfile.dev` with Solid Queue `jobs:` entry and `queue.yml` with `recurring_schedule` dispatcher wiring (idempotent, skip if already present).
- `RecurringScheduleVerifier` checks that recurring tasks are registered with Solid Queue dispatchers; `SolidQueueVerifier` remediation now mentions `Procfile.dev` for `bin/dev` users.
- Dashboard fetch log entries display source URL (domain for RSS, item URL for scrapes) alongside existing summary.
- External links across dashboard, logs, sources, and items open in new tab with visual indicator icon.
- Configurable Active Storage image downloads: `config.images.download_to_active_storage` (default `false`) detects inline images in feed content, downloads them via background job, and rewrites `<img>` src attributes with Active Storage URLs.
- `Images::ContentRewriter` extracts and rewrites image URLs from HTML content using Nokolexbor.
- `Images::Downloader` service validates content type and size before downloading images.
- `DownloadContentImagesJob` orchestrates the download/attach/rewrite pipeline per item.
- SSL certificate store configuration: every Faraday connection gets an `OpenSSL::X509::Store` initialized with `set_default_paths`, resolving "unable to get local issuer certificate" errors on systems with incomplete CA bundles.
- Configurable SSL options in `HTTPSettings`: `ssl_ca_file`, `ssl_ca_path`, `ssl_verify` for non-standard certificate environments.
- Netflix Tech Blog VCR cassette regression test proving Medium-hosted RSS feeds parse correctly with the SSL fix.

### Fixed

- SSL certificate verification failures for feeds hosted on services requiring intermediate CAs (e.g., Netflix Tech Blog via Medium/AWS).
- Setup documentation now includes `Procfile.dev` and `recurring_schedule` guidance.

### Changed

- Updated `sm-host-setup`, `sm-configure`, and setup documentation to reflect that the generator handles Procfile.dev and recurring_schedule automatically.

### Testing

- 973 tests, 3,114 assertions, 0 failures (up from 841 tests in 0.3.3).
- RuboCop: 389 files, 0 offenses.
- Brakeman: 0 warnings.

## [0.3.3] - 2026-02-11

### Fixed

- Added missing `recurring.yml` configuration to the install generator so host apps get Solid Queue recurring job config on install.
- Fixed YAML alias parsing in install generator so merging into existing `recurring.yml` files with `<<: *default` anchors works correctly.

### Changed

- Updated `sm-host-setup` and `sm-job` skills to reflect latest conventions.
- Updated setup documentation with current installation steps.

## [0.3.2] - 2026-02-10

### Fixed

- Updated README, AGENTS.md, CONTRIBUTING.md, and docs/ to reflect v0.3.1 changes (Ruby 4.0+, gem version refs, skills system documentation).
- Replaced stale `.ai/` references with `CLAUDE.md` and `AGENTS.md` across all docs.
- Corrected `SOURCE_MONITOR_TEST_WORKERS` env var to `PARALLEL_WORKERS` in CONTRIBUTING.md.
- Removed historical agent development notes from AGENTS.md.
- Condensed verbose clean coding guidelines into concise bullet summary.

## [0.3.1] - 2026-02-10

### Added

- 14 engine-specific Claude Code skills (`sm-*` prefix) for contributors and consumers.
- Skills installer with consumer/contributor groups via rake tasks.
- Skills installation integrated into guided `bin/source_monitor install` workflow.
- Skills packaged in gem for distribution to host apps.

## [0.3.0] - 2026-02-10

### Changed

- Upgraded to Ruby 4.0.1 and Rails 8.1.2.
- Refactored FeedFetcher from 627 to 285 lines by extracting SourceUpdater, AdaptiveInterval, and EntryProcessor sub-modules.
- Refactored Configuration from 655 to 87 lines by extracting 12 dedicated settings files.
- Refactored ImportSessionsController from 792 to 295 lines by extracting 4 concerns.
- Refactored ItemCreator from 601 to 174 lines by extracting EntryParser and ContentExtractor.
- Replaced 66 eager requires with 11 explicit + 71 Ruby autoload declarations in lib/source_monitor.rb.
- Removed hard-coded LogEntry table name in favor of ModelExtensions.register.

### Removed

- Dead code: SourcesController fetch/retry methods, duplicate new/create actions, duplicate test file.

### Fixed

- Test isolation: scoped queries to prevent cross-test contamination in parallel runs.
- RuboCop: added frozen_string_literal pragma to all Ruby files; zero offenses.
- Coverage baseline reduced from 2117 to 510 uncovered lines (75.9% reduction).

### Testing

- 841 tests, 2776 assertions, 0 failures.
- RuboCop: 369 files, 0 offenses.
- Brakeman: 0 warnings.

## [0.2.0] - 2025-11-25

### Added

- OPML import wizard with multi-step flow (upload, preview with selection, health checks, bulk configure, confirm) and Turbo-powered navigation.
- Health check enqueuing for selected feeds plus realtime Turbo Stream row/progress updates during the wizard.
- Bulk configuration reuse of source form fields with identity fields hidden for batch apply.
- Background OPML import job with ImportHistory persistence, per-source success/failure/duplicate tracking, and Turbo broadcast of results to the Sources index.
- Sources index “Recent OPML import” panel surfacing latest ImportHistory (counts, failures).

### Changed

- Shared source params helper for defaults/permitted attributes to drive bulk settings and single-source forms consistently.
- Wizard fallback auth handling for unauthenticated host apps to enable usage in simple dummy setups.

### Testing

- `rbenv exec bundle exec rubocop`
- `rbenv exec ruby bin/rails test`
- `./bin/test-coverage`
- `rbenv exec ruby bin/check-diff-coverage`

## [0.1.3] - 2025-11-13

### Added

- Clarified installation instructions for consumers: add `gem "source_monitor"` via RubyGems before running the guided workflow (README + docs/setup.md).

### Testing

- Documentation-only update; no code changes.

## [0.1.2] - 2025-11-13

### Added

- Guided setup workflow (`bin/source_monitor install`) with dependency checks, Gemfile automation, migration deduplication, initializer patching, and Devise prompt support.
- Reusable verification tooling (`bin/source_monitor verify` / `bin/rails source_monitor:setup:verify`) plus Solid Queue/Action Cable verifiers, JSON output, and optional telemetry logging.
- Fresh documentation (`docs/setup.md`, rollout checklist in `docs/deployment.md`, validation log) outlining prerequisites, rollback steps, and CI adoption guidance.

### Fixed

- Enforced coverage/diff checks in CI, added `bin/check-setup-tests`, and expanded test suites so new setup workflow files stay covered.
- Hardened host harness env defaults to avoid `root` Postgres role errors during CI/app template generation.

### Testing

- Full suite (`bin/rails test`), `bin/test-coverage`, `bin/check-diff-coverage`, and `bin/rubocop` all pass on Ruby 3.4.4.

## [0.1.1] - 2025-11-09

### Changed

- Bumped the gem to 0.1.1 so the republished package on RubyGems matches the revamped 0.1.0 release notes without reusing the yanked version number.

### Fixed

- Clarified that the 0.1.0 entry now reflects the authoritative feature overview for the first release, preventing consumers from encountering inconsistent documentation across yanks.

## [0.1.0] - 2025-11-08

### Added

- Shipped the initial SourceMonitor mountable Rails engine with Source and Item models, Tailwind-powered admin UI, Turbo-powered dashboards, and a dummy host app for full-stack validation.
- Implemented the full feed ingestion pipeline: Feedjira-based fetcher, Faraday HTTP stack with retry/timeout controls, adaptive scheduling, structured error types, retention policies, and fetch log instrumentation surfaced in the UI.
- Introduced comprehensive scraping support with a scraper adapter base class, Readability parser, dedicated `ItemContent` storage, manual/bulk scrape controls, and queue-backed `ScrapeItemJob` orchestration.
- Established Solid Queue and Solid Cable defaults, including recurring schedule config, Mission Control hooks, `FetchFeedJob`/`ScheduleFetchesJob`, queue metrics dashboards, and helper APIs for namespaced queue names.
- Added health monitoring, failure recovery controls, analytics widgets (heatmaps, distribution insights), and notification hooks so operators can triage outages and re-run work with confidence.
- Delivered install tooling—generator, initializer template, cleanup/retention rake tasks, host harness smoke tests, and example host templates—plus Faraday/HTTP, scraper, retention, realtime, and mission control configuration DSLs.

### Changed

- Rebranded the engine, routes, and namespaces to `SourceMonitor`, aligning configuration defaults, installer output, and docs with the new identity.
- Modernized the asset and JavaScript pipeline (esbuild, bundler, Stimulus fixes) and widened admin layouts, sortable tables, and bulk action UX for better operator ergonomics.
- Restructured source member actions into nested REST resources (fetch, retry, bulk scrape) and consolidated log views/analytics for clearer operator workflows.

### Fixed

- Hardened scheduler behavior to avoid duplicate catch-up fetches, ensured stalled fetch recovery paths requeue work, and guaranteed fetch failure callbacks always attach logs/state.
- Resolved Solid Cable initialization issues, host Action Cable dependencies, and dummy host/environment parity problems so realtime updates function out of the box.
- Stabilized the host harness across Ruby versions, added Postgres-backed CI services, patched rbenv mismatches, and tightened sqlite shims plus asset/database setup to keep tests green on every platform.

### Documentation

- Published install and upgrade guides, roadmap phase notes, PR workflow requirements, health configuration guidance, and mission control instructions; expanded AGENT guidance for future contributors.

### CI/CD

- Added layered coverage guardrails (diff coverage enforcement, result-set merging, targeted health coverage suites), automated release verification, and artifact preservation across the packaging workflow.
- Upgraded GitHub Actions dependencies, introduced reusable workflows for test/lint/build jobs, and ensured release verification prepares databases, locks dependencies, and emits the packaged gem.

### Upgrade Notes

1. Add `gem "source_monitor", "~> 0.1.0"` to your host `Gemfile` and run `rbenv exec bundle install`.
2. Execute `rbenv exec bin/rails railties:install:migrations FROM=source_monitor` followed by `rbenv exec bin/rails db:migrate` to copy and run Solid Queue + SourceMonitor migrations.
3. Review `config/initializers/source_monitor.rb` for queue, scraping, retention, HTTP, and Mission Control settings; adjust the generated defaults to fit your environment.
4. If you surface Mission Control Jobs from the dashboard, ensure `mission_control-jobs` stays mounted and `SourceMonitor.mission_control_dashboard_path` resolves correctly.
5. Restart Solid Queue workers, Solid Cable (or Redis Action Cable), and any recurring job runners to pick up the new engine version.
