# Configuration & API Reference

All configuration lives in `SourceMonitor.configure`—the install generator creates `config/initializers/source_monitor.rb` with sensible defaults and inline documentation. This guide expands on every namespace so you know which knobs to turn in production.

```ruby
SourceMonitor.configure do |config|
  # customize settings here
end
```

Restart your application whenever you change these settings. The engine reloads model extensions automatically when the block runs, but background processes need a restart to pick up queue name or adapter changes.

## Asset Bundling

- SourceMonitor ships with npm-based bundling via `cssbundling-rails` and `jsbundling-rails`; follow `.ai/engine-asset-configuration.md:11-113` when adjusting dependency versions or adding new entrypoints.
- Keep bundled outputs under the namespaced directories (`app/assets/builds/source_monitor`, `images/source_monitor`, `svgs/source_monitor`) so host apps avoid collisions. See `.ai/engine-asset-configuration.md:32-44` for the layout recommendations.
- Use `rbenv exec bundle exec rake app:source_monitor:assets:build` (or `npm run build`) after tweaking Tailwind/Stimulus code to refresh the builds, and rely on `test/dummy/bin/dev` to watch `build:css:watch` + `build:js:watch` during development.
- Sprockets hosts receive automatic precompile coverage; if a host prefers manifest-based precompilation, adapt the approach documented in `.ai/engine-asset-configuration.md:114-143`.

## Queue & Worker Settings

- `config.queue_namespace` – prefix applied to queue names (`"source_monitor"` by default)
- `config.fetch_queue_name` / `config.scrape_queue_name` – base queue names before the host's `ActiveJob.queue_name_prefix` is applied
- `config.fetch_queue_concurrency` / `config.scrape_queue_concurrency` – advisory values Solid Queue uses for per-queue limits
- `config.maintenance_queue_name` – queue name for maintenance jobs (`"source_monitor_maintenance"` by default)
- `config.maintenance_queue_concurrency` – advisory concurrency for the maintenance queue (default `1`)
- `config.queue_name_for(:fetch | :scrape | :maintenance)` – helper that respects the host's queue prefix

Use the helpers exposed on `SourceMonitor`:

```ruby
SourceMonitor.queue_name(:fetch)         # => "source_monitor_fetch"
SourceMonitor.queue_name(:maintenance)   # => "source_monitor_maintenance"
SourceMonitor.queue_concurrency(:scrape) # => 2
```

## Job Metrics & Mission Control

- `config.job_metrics_enabled` – toggles Solid Queue metrics collection for the dashboard cards (default `true`)
- `config.mission_control_enabled` – surfaces the Mission Control link on the dashboard when `true`
- `config.mission_control_dashboard_path` – host route helper or callable returning the Mission Control path/URL; left blank by default

The helper `SourceMonitor.mission_control_dashboard_path` performs a routing check so the dashboard only renders links that resolve.

## HTTP Client Settings

`config.http` maps directly onto Faraday's middleware options.

- `timeout` – total request timeout in seconds (default `15`)
- `open_timeout` – connection open timeout in seconds (`5`)
- `max_redirects` – maximum redirects to follow (`5`)
- `user_agent` – defaults to `Mozilla/5.0 (compatible; SourceMonitor/<version>)` (browser-like to avoid bot-blocking)
- `proxy` – hash or URL to configure proxy usage
- `headers` – hash (or callables) merged into every request
- `retry_max`, `retry_interval`, `retry_interval_randomness`, `retry_backoff_factor`, `retry_statuses` – mapped to `faraday-retry`

## Fetching Behaviour

`config.fetching` controls adaptive scheduling.

- `min_interval_minutes` / `max_interval_minutes` – enforce floor/ceiling for automatic schedule adjustments (defaults: `5` and `1440`)
- `increase_factor` / `decrease_factor` – multipliers when a source trends slow/fast
- `failure_increase_factor` – multiplier applied on consecutive failures
- `jitter_percent` – random jitter applied to next fetch time (0.1 = ±10%)
- `scheduler_batch_size` – max sources picked up per scheduler run (default `25`, was `100`)
- `stale_timeout_minutes` – minutes before a source stuck in "fetching" is reset (default `5`, was `10`)

## Retention Defaults

`config.retention` sets global defaults that sources inherit when their fields are blank.

- `items_retention_days` – prune items older than this many days (`nil` = retain forever)
- `max_items` – keep only the most recent N items (`nil` = unlimited)
- `strategy` – `:destroy` or `:soft_delete` (defaults to `:destroy` in the configuration class; the installer comments demonstrate `:soft_delete`)

The retention pruner runs after every successful fetch and inside nightly cleanup jobs.

## Scraper Registry

Register adapters that inherit from `SourceMonitor::Scrapers::Base`:

```ruby
config.scrapers.register(:readability, SourceMonitor::Scrapers::Readability)
config.scrapers.register(:custom, "MyApp::Scrapers::Premium" )
```

Adapters receive merged settings (`default -> source -> invocation`), and must return a `SourceMonitor::Scrapers::Result` object. Use `config.scrapers.unregister(:custom)` to remove overrides.

## Events & Item Processors

Respond to lifecycle events without monkey patching:

```ruby
config.events.after_item_created do |event|
  Analytics.track_new_item(event.item, source: event.source)
end

config.events.after_fetch_completed do |event|
  Rails.logger.info("Feed #{event.source.name} finished with #{event.status}")
end

config.events.register_item_processor ->(context) {
  SearchIndexer.index(context.item)
}
```

Event structs expose `item`, `source`, `entry`, `result`, `status`, and `occurred_at`. Item processors run after events and receive an `ItemProcessorContext` with the same shape.

## Model Extensions

`config.models` lets host apps customise engine models at load time.

- `config.models.table_name_prefix` – override the default `sourcemon_` prefix
- `config.models.source.include_concern "MyApp::SourceMonitor::SourceExtensions"` – mix in concerns before models load
- `config.models.source.validate :ensure_metadata_rules` – register validations (blocks or symbols)
- Equivalent hooks exist for items, fetch logs, scrape logs, and item content via `config.models.item`, etc.

The engine reloads model extensions whenever configuration runs so code reloading in development continues to work.

## Realtime Settings

`config.realtime` governs Action Cable transport.

- `config.realtime.adapter` – one of `:solid_cable`, `:redis`, or `:async`
- `config.realtime.redis_url` – optional Redis URL when using the Redis adapter
- `config.realtime.solid_cable` – yields options: `polling_interval`, `message_retention`, `autotrim`, `use_skip_locked`, `trim_batch_size`, `connects_to` (hash for multi-database setups), `silence_polling`

Call `config.realtime.action_cable_config` if you need a full hash for environment-specific `cable.yml` generation.

## Authentication Helpers

Protect the dashboard with host-specific auth in one place:

```ruby
config.authentication.authenticate_with :authenticate_admin!
config.authentication.authorize_with ->(controller) {
  controller.current_user&.feature_enabled?(:source_monitor)
}
config.authentication.current_user_method = :current_user
config.authentication.user_signed_in_method = :user_signed_in?
```

Handlers can be symbols (invoked on the controller) or callables. Return `false` or raise to deny access.

## Health Model

`config.health` tunes automatic pause/resume heuristics.

- `window_size` – number of fetch attempts to evaluate (default `20`)
- `healthy_threshold` / `warning_threshold` – ratios that drive UI badges
- `auto_pause_threshold` / `auto_resume_threshold` – percentages that trigger automatic toggling
- `auto_pause_cooldown_minutes` – grace period before re-enabling a source

## Helper APIs

- `SourceMonitor.configure` – run-time configuration entry point
- `SourceMonitor.reset_configuration!` – revert to defaults (useful in tests)
- `SourceMonitor.events` – direct access to the events registry
- `SourceMonitor.queue_name(role)` / `SourceMonitor.queue_concurrency(role)` – convenience helpers
- `SourceMonitor::Metrics.snapshot` – inspect counters/gauges (great for health checks)

## Environment Variables

The engine honours several environment variables out of the box:

- `SOLID_QUEUE_SKIP_RECURRING` – skip loading `config/recurring.yml`
- `SOLID_QUEUE_RECURRING_SCHEDULE_FILE` – alternative schedule file path
- `SOFT_DELETE` / `SOURCE_IDS` / `SOURCE_ID` – overrides for item cleanup rake tasks
- `FETCH_LOG_DAYS` / `SCRAPE_LOG_DAYS` – retention windows for log cleanup
- `WINDOW_MINUTES` – time window (minutes) for `stagger_fetch_times` rake task (default `10`)
- `SOURCE_MONITOR_FETCH_CONCURRENCY` – override fetch queue concurrency in `solid_queue.yml`
- `SOURCE_MONITOR_SCRAPE_CONCURRENCY` – override scrape queue concurrency in `solid_queue.yml`
- `SOURCE_MONITOR_MAINTENANCE_CONCURRENCY` – override maintenance queue concurrency in `solid_queue.yml`

## After Changing Configuration

1. Restart web and worker processes so Solid Queue picks up new queue names/adapters.
2. Re-run `npm run build` (engine root) and `bin/rails assets:precompile` if you adjust engine assets per `.ai/engine-asset-configuration.md:11-188`.
3. Keep a regression test per configuration extension—for example, ensure custom validations are exercised in MiniTest.
