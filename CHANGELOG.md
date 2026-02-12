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
