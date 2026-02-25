# SourceMonitor

SourceMonitor is a production-ready Rails 8 mountable engine for ingesting, normalising, scraping, and monitoring RSS/Atom/JSON feeds. It ships with a Tailwind-powered admin UI, Solid Queue job orchestration, Solid Cable realtime broadcasting, and an extensible configuration layer so host applications can offer full-stack feed operations without rebuilding infrastructure.

> **Note:** Application developers consume SourceMonitor via RubyGems—add the gem to your host application's Gemfile and follow the guided installer. Clone this repository only when contributing to the engine itself.

## Installation (RubyGems)

In your host Rails app:

```bash
bundle add source_monitor --version "~> 0.10.0"
# or add `gem "source_monitor", "~> 0.10.0"` manually, then run:
bundle install
```

This exposes `bin/source_monitor` (via Bundler binstubs) so you can run the guided workflow described below.

## Highlights
- Full-featured source and item administration backed by Turbo Streams and Tailwind UI components
- Adaptive fetch pipeline (Feedjira + Faraday) with conditional GETs, retention pruning, and scrape orchestration
- Automatic source favicons via Active Storage with multi-strategy discovery and graceful fallback
- Realtime dashboard metrics, batching/caching query layer, and Mission Control integration hooks
- Smart toast notification stacking (max 3 visible, "+N more" overflow badge, click-to-expand)
- Extensible scraper adapters (Readability included) with per-source settings and structured result metadata
- Declarative configuration DSL covering queues, HTTP, retention, events, model extensions, authentication, and realtime transports
- First-class observability through ActiveSupport notifications and `SourceMonitor::Metrics` counters/gauges

## Requirements
- Ruby 4.0+ (we recommend [rbenv](https://github.com/rbenv/rbenv) for local development, but use whatever Ruby version manager suits your environment—asdf, chruby, rvm, or container-based workflows all work fine)
- Rails ≥ 8.0.2.1 in the host application
- PostgreSQL 13+ (engine migrations use JSONB, SKIP LOCKED, advisory locks, and Solid Cable tables)
- Node.js 18+ (npm or Yarn) for asset linting and the Tailwind/esbuild bundling pipeline
- Solid Queue workers (Rails 8 default) and Solid Cable (default realtime adapter)
- Optional: Mission Control Jobs for dashboard linking, Redis if you opt into the Redis realtime adapter

## Quick Start (Host Application)

> **Command prefixes:** Examples below show bare `bundle`, `bin/rails`, and `bin/source_monitor`. If you use rbenv/asdf or containerized tooling, prefix/adjust commands accordingly so they run inside your Ruby environment.

### Install the Gem

Before running any SourceMonitor commands inside your host app, add the gem and install dependencies:

```bash
bundle add source_monitor --version "~> 0.10.0"
# or edit your Gemfile, then run
bundle install
```

### Recommended: Guided Workflow
1. **Optional prerequisite check:** `bin/rails source_monitor:setup:check`
2. **Run the guided installer:** `bin/source_monitor install --yes`
   - Prompts for the mount path (default `/source_monitor`), adds the gem entry when missing, runs `bundle install`, `npm install` (when `package.json` exists), copies/deduplicates migrations, patches the initializer, and runs verification.
3. **Start workers / scheduler:** `bin/rails solid_queue:start` and, if you use recurring jobs, `bin/jobs --recurring_schedule_file=config/recurring.yml`.
4. **Verify anytime:** `bin/source_monitor verify` (also exposed as `bin/rails source_monitor:setup:verify`). The command prints a human summary plus JSON so CI can gate on Solid Queue and Action Cable health.
5. **Visit the dashboard** at the chosen mount path and trigger “Fetch Now” on a source to confirm everything is wired.

See [docs/setup.md](docs/setup.md) for the full workflow (prereq table, gem installation, rollback steps, telemetry flag, Devise system test template).

### Manual Install (Advanced)
Prefer explicit Rails generator steps or need to customize each phase? The same document covers a full **Manual Installation** section so you can copy/paste each command into bespoke pipelines.

Troubleshooting advice lives in [docs/troubleshooting.md](docs/troubleshooting.md).

### Upgrading SourceMonitor
1. Bump the gem version in your host `Gemfile` and run `bundle install` (or `bundle update source_monitor` when targeting a specific release).
2. Re-run `bin/rails railties:install:migrations FROM=source_monitor` and then `bin/rails db:migrate` to pick up schema changes.
3. Compare your `config/initializers/source_monitor.rb` against the newly generated template for configuration diffs (new queue knobs, HTTP options, etc.).
4. Review release notes for optional integrations—when enabling Mission Control, ensure `mission_control-jobs` stays mounted and linked via `config.mission_control_dashboard_path`.
5. Smoke test Solid Queue workers, Action Cable, and admin UI flows after the upgrade, and run `bin/source_monitor verify` so CI/deploys confirm workers/cable health before rollout.

## Example Applications
- `examples/basic_host/template.rb` – Minimal host that seeds a Rails blog source and redirects `/` to the dashboard.
- `examples/advanced_host/template.rb` – Production-style integration with Mission Control, Redis realtime, Solid Queue tuning, and metrics endpoint.
- `examples/custom_adapter/template.rb` – Registers the sample Markdown scraper adapter and seeds a Markdown-based source.
- `examples/docker` – Dockerfile, Compose stack, and entrypoint script that run any generated example alongside Postgres and Redis.

See [examples/README.md](examples/README.md) for usage instructions.

## Architecture at a Glance
- **Source Lifecycle** – `SourceMonitor::Fetching::FetchRunner` coordinates advisory locking, fetch execution, retention pruning, and scrape enqueues. Source models store health metrics, failure states, and adaptive scheduling parameters.
- **Item Processing** – `SourceMonitor::Items::RetentionPruner`, `SourceMonitor::Scraping::Enqueuer`, and `SourceMonitor::Scraping::ItemScraper` keep content fresh, ensure deduplicated storage, and capture scrape metadata/logs.
- **Scraping Pipeline** – Adapters inherit from `SourceMonitor::Scrapers::Base`, merging default + source + invocation settings and returning structured results. The bundled Readability adapter composes `SourceMonitor::Scrapers::Fetchers::HttpFetcher` and `SourceMonitor::Scrapers::Parsers::ReadabilityParser`.
- **Realtime Dashboard** – `SourceMonitor::Dashboard::Queries` batches SQL, caches per-request responses, emits instrumentation (`source_monitor.dashboard.*`), and coordinates Turbo broadcasts via Solid Cable.
- **Observability** – `SourceMonitor::Metrics` tracks counters/gauges for fetches, scheduler runs, and dashboard activity. ActiveSupport notifications (`source_monitor.fetch.*`, `source_monitor.scheduler.run`, etc.) let you instrument external systems without monkey patches.
- **Extensibility** – `SourceMonitor.configure` exposes namespaces for queue tuning, HTTP defaults, scraper registry, retention, event callbacks, model extensions, authentication hooks, realtime transports, health thresholds, and job metrics.

## Admin Experience
- Dashboard cards summarising source counts, recent activity, queue visibility, and upcoming fetch schedules
- Source CRUD with scraping toggles, adaptive fetch controls, manual fetch triggers, and detailed fetch log timelines
- Item explorer showing feed vs scraped content, scrape status badges, and manual scrape actions via Turbo
- Fetch/scrape log viewers with HTTP status, duration, backtrace, and Solid Queue job references

## Background Jobs & Scheduling
- Solid Queue becomes the Active Job adapter when the host app still uses the inline `:async` adapter. Three queues are used: `source_monitor_fetch` (FetchFeedJob, ScheduleFetchesJob), `source_monitor_scrape` (ScrapeItemJob), and `source_monitor_maintenance` (health checks, cleanup, favicon, images, OPML import). All honour `ActiveJob.queue_name_prefix`.
- `config/recurring.yml` schedules minute-level fetches and scrapes. Run `bin/jobs --recurring_schedule_file=config/recurring.yml` (or set `SOLID_QUEUE_RECURRING_SCHEDULE_FILE`) to load recurring tasks. Disable with `SOLID_QUEUE_SKIP_RECURRING=true`.
- Retry/backoff behaviour is driven by `SourceMonitor.configure.fetching`. Scheduler batch size (default 25) and stale fetch timeout (default 5 minutes) are configurable for small-server deployments. Fetch completion events and item processors allow you to chain downstream workflows (indexing, notifications, etc.).

## Configuration & API Surface
The generated initializer documents every setting. Key areas:

- Queue namespace/concurrency helpers (`SourceMonitor.queue_name(:fetch)`, `:scrape`, `:maintenance`)
- HTTP, retry, and proxy settings (Faraday-backed)
- Scraper registry (`config.scrapers.register(:my_adapter, "MyApp::Scrapers::Custom")`)
- Retention defaults (`config.retention.items_retention_days`, `config.retention.strategy`)
- Lifecycle hooks (`config.events.after_item_created`, `config.events.register_item_processor`)
- Model extensions (table prefixes, included concerns, custom validations)
- Realtime adapter selection (`config.realtime.adapter = :solid_cable | :redis | :async`)
- Authentication helpers (`config.authentication.authenticate_with`, `authorize_with`, etc.)
- Mission Control toggles (`config.mission_control_enabled`, `config.mission_control_dashboard_path`)
- Health thresholds driving automatic pause/resume

See [docs/configuration.md](docs/configuration.md) for exhaustive coverage and examples.

## Claude Code Skills

SourceMonitor ships 15 engine-specific Claude Code skills (`sm-*` prefix) that give AI agents deep context about the engine's domain model, configuration DSL, pipeline stages, and testing conventions. Skills are bundled with the gem and installed into your host app's `.claude/skills/` directory.

```bash
bin/rails source_monitor:skills:install        # Consumer skills (host app integration)
bin/rails source_monitor:skills:contributor     # Contributor skills (engine development)
bin/rails source_monitor:skills:all            # All skills
bin/rails source_monitor:skills:remove         # Remove all sm-* skills
```

The guided installer (`bin/source_monitor install`) also offers to install consumer skills as part of the setup workflow.

## Deployment Considerations
- Copy engine migrations before every deploy and run `bin/rails db:migrate`.
- Precompile assets so SourceMonitor's bundled CSS/JS outputs are available at runtime.
- Run dedicated Solid Queue worker processes; consider a separate scheduler process for recurring jobs.
- Configure Action Cable (Solid Cable by default) and expose `/cable` through your load balancer.
- Monitor gauges/counters emitted by `SourceMonitor::Metrics` and subscribe to notifications for alerting.

More production guidance, including process topology and scaling tips, is available in [docs/deployment.md](docs/deployment.md).

## Troubleshooting & Support
Common installation and runtime issues (missing migrations, realtime not streaming, scraping failures, queue visibility gaps) are documented in [docs/troubleshooting.md](docs/troubleshooting.md). When you report bugs, include your `SourceMonitor::VERSION`, Rails version, configuration snippet, and relevant fetch/scrape logs so we can reproduce quickly.

## Development & Testing (Engine Repository)
- Install dependencies with `bundle install` and `npm install` (prefix with `rbenv exec` if using rbenv).
- Use `test/dummy/bin/dev` to boot the dummy app with npm CSS/JS watchers, Solid Queue worker, and Rails server.
- Run tests via `bin/test-coverage` (SimpleCov-enforced), `bundle exec rake app:test:smoke` for the fast subset, or `bin/rails test` for targeted suites.
- Quality checks: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/lint-assets`.
- Record HTTP fixtures with VCR under `test/vcr_cassettes/` and keep coverage ≥ 90% for new code.

Contributions follow the clean architecture and TDD guidelines in `CLAUDE.md` and `AGENTS.md`.

## License
SourceMonitor is released under the [MIT License](MIT-LICENSE).
