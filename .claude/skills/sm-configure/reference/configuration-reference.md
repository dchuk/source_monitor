# Configuration Reference

Complete reference for every SourceMonitor configuration setting.

Source: `lib/source_monitor/configuration.rb` and `lib/source_monitor/configuration/*.rb`

## Top-Level Settings

Defined on `SourceMonitor::Configuration`:

| Setting | Type | Default | Description |
|---|---|---|---|
| `queue_namespace` | String | `"source_monitor"` | Prefix for queue names and instrumentation keys |
| `fetch_queue_name` | String | `"source_monitor_fetch"` | Queue name for fetch jobs |
| `scrape_queue_name` | String | `"source_monitor_scrape"` | Queue name for scrape jobs |
| `fetch_queue_concurrency` | Integer | `2` | Advisory concurrency for fetch queue |
| `scrape_queue_concurrency` | Integer | `2` | Advisory concurrency for scrape queue |
| `recurring_command_job_class` | String/Class/nil | `nil` | Override Solid Queue recurring task job class |
| `job_metrics_enabled` | Boolean | `true` | Toggle queue metrics on dashboard |
| `mission_control_enabled` | Boolean | `false` | Show Mission Control link on dashboard |
| `mission_control_dashboard_path` | String/Proc/nil | `nil` | Path or callable returning MC URL |

| `maintenance_queue_name` | String | `"source_monitor_maintenance"` | Queue name for maintenance jobs |
| `maintenance_queue_concurrency` | Integer | `1` | Advisory concurrency for maintenance queue |

### Methods

| Method | Signature | Description |
|---|---|---|
| `queue_name_for` | `(role) -> String` | Returns resolved queue name with host prefix (`:fetch`, `:scrape`, or `:maintenance`) |
| `concurrency_for` | `(role) -> Integer` | Returns concurrency for `:fetch`, `:scrape`, or `:maintenance` |

---

## HTTP Settings (`config.http`)

Class: `SourceMonitor::Configuration::HTTPSettings`

| Setting | Type | Default | Description |
|---|---|---|---|
| `timeout` | Integer | `15` | Total request timeout (seconds) |
| `open_timeout` | Integer | `5` | Connection open timeout (seconds) |
| `max_redirects` | Integer | `5` | Maximum redirects to follow |
| `user_agent` | String | `"SourceMonitor/<version>"` | User-Agent header |
| `proxy` | String/Hash/nil | `nil` | HTTP proxy configuration |
| `headers` | Hash | `{}` | Extra headers merged into every request |
| `retry_max` | Integer | `4` | Maximum retry attempts |
| `retry_interval` | Float | `0.5` | Initial retry delay (seconds) |
| `retry_interval_randomness` | Float | `0.5` | Randomness factor for retry jitter |
| `retry_backoff_factor` | Integer | `2` | Exponential backoff multiplier |
| `retry_statuses` | Array/nil | `nil` | HTTP status codes to retry (nil = use defaults) |

```ruby
config.http.timeout = 30
config.http.proxy = "http://proxy.example.com:8080"
config.http.headers = { "X-Custom" => "value" }
config.http.retry_statuses = [429, 500, 502, 503, 504]
```

---

## Fetching Settings (`config.fetching`)

Class: `SourceMonitor::Configuration::FetchingSettings`

Controls adaptive fetch scheduling.

| Setting | Type | Default | Description |
|---|---|---|---|
| `min_interval_minutes` | Integer | `5` | Minimum fetch interval (minutes) |
| `max_interval_minutes` | Integer | `1440` | Maximum fetch interval (24 hours) |
| `increase_factor` | Float | `1.25` | Multiplier when source trends slow (no new items) |
| `decrease_factor` | Float | `0.75` | Multiplier when new items arrive |
| `failure_increase_factor` | Float | `1.5` | Multiplier on consecutive failures |
| `jitter_percent` | Float | `0.1` | Random jitter (+/-10%, 0 disables) |
| `scheduler_batch_size` | Integer | `25` | Max sources per scheduler run |
| `stale_timeout_minutes` | Integer | `5` | Minutes before stuck "fetching" source is reset |

```ruby
config.fetching.min_interval_minutes = 10
config.fetching.max_interval_minutes = 720  # 12 hours
config.fetching.jitter_percent = 0.15       # +/-15%
config.fetching.scheduler_batch_size = 50   # Increase for larger servers
config.fetching.stale_timeout_minutes = 3   # Faster recovery
```

---

## Health Settings (`config.health`)

Class: `SourceMonitor::Configuration::HealthSettings`

Tunes automatic pause/resume heuristics per source.

| Setting | Type | Default | Description |
|---|---|---|---|
| `window_size` | Integer | `20` | Number of fetch attempts to evaluate |
| `healthy_threshold` | Float | `0.8` | Success ratio for "healthy" badge |
| `warning_threshold` | Float | `0.5` | Success ratio for "warning" badge |
| `auto_pause_threshold` | Float | `0.2` | Auto-pause source below this ratio |
| `auto_resume_threshold` | Float | `0.6` | Auto-resume source above this ratio |
| `auto_pause_cooldown_minutes` | Integer | `60` | Grace period before re-enabling |

```ruby
config.health.window_size = 50
config.health.auto_pause_threshold = 0.1
config.health.auto_pause_cooldown_minutes = 120
```

---

## Scraper Registry (`config.scrapers`)

Class: `SourceMonitor::Configuration::ScraperRegistry`

Manages scraper adapter registration. Adapters must inherit from `SourceMonitor::Scrapers::Base`.

### Methods

| Method | Signature | Description |
|---|---|---|
| `register` | `(name, adapter)` | Register adapter by name (symbol/string) |
| `unregister` | `(name)` | Remove adapter by name |
| `adapter_for` | `(name) -> Class/nil` | Look up adapter class |
| `each` | `(&block)` | Iterate registered adapters |

Names are normalized to lowercase alphanumeric + underscore.

Adapters can be a Class or a String (constantized lazily).

```ruby
config.scrapers.register(:custom, MyApp::Scrapers::Custom)
config.scrapers.register(:premium, "MyApp::Scrapers::Premium")
config.scrapers.unregister(:readability)
```

---

## Retention Settings (`config.retention`)

Class: `SourceMonitor::Configuration::RetentionSettings`

Global defaults inherited by sources with blank retention fields.

| Setting | Type | Default | Description |
|---|---|---|---|
| `items_retention_days` | Integer/nil | `nil` | Prune items older than N days (nil = keep forever) |
| `max_items` | Integer/nil | `nil` | Keep only N most recent items (nil = unlimited) |
| `strategy` | Symbol | `:destroy` | Pruning strategy: `:destroy` or `:soft_delete` |

```ruby
config.retention.items_retention_days = 90
config.retention.max_items = 1000
config.retention.strategy = :soft_delete
```

---

## Scraping Settings (`config.scraping`)

Class: `SourceMonitor::Configuration::ScrapingSettings`

| Setting | Type | Default | Description |
|---|---|---|---|
| `max_in_flight_per_source` | Integer/nil | `25` | Max concurrent scrapes per source |
| `max_bulk_batch_size` | Integer/nil | `100` | Max items per bulk scrape enqueue |

Values are normalized to positive integers. Set to `nil` to disable limits.

```ruby
config.scraping.max_in_flight_per_source = 50
config.scraping.max_bulk_batch_size = 200
```

---

## Events (`config.events`)

Class: `SourceMonitor::Configuration::Events`

Register lifecycle callbacks. See the `sm-event-handler` skill for full event documentation.

### Callback Methods

| Method | Signature | Description |
|---|---|---|
| `after_item_created` | `(handler=nil, &block)` | Called after a new item is created from a feed entry |
| `after_item_scraped` | `(handler=nil, &block)` | Called after an item is scraped for content |
| `after_fetch_completed` | `(handler=nil, &block)` | Called after a feed fetch finishes |
| `register_item_processor` | `(processor=nil, &block)` | Register a post-processing pipeline step |
| `callbacks_for` | `(name) -> Array` | Retrieve callbacks for an event |
| `item_processors` | `-> Array` | Retrieve registered item processors |
| `reset!` | `-> void` | Clear all callbacks and processors |

Handlers must respond to `#call`. Can be a Proc, lambda, or any callable object.

```ruby
config.events.after_item_created ->(event) { log(event.item) }
config.events.after_fetch_completed do |event|
  StatsTracker.record(event.source, event.status)
end
```

---

## Models (`config.models`)

Class: `SourceMonitor::Configuration::Models`

Per-model extension points for host apps.

| Setting | Type | Default | Description |
|---|---|---|---|
| `table_name_prefix` | String | `"sourcemon_"` | Table name prefix for all engine tables |

### Model Accessors

| Method | Key | Engine Model |
|---|---|---|
| `config.models.source` | `:source` | `SourceMonitor::Source` |
| `config.models.item` | `:item` | `SourceMonitor::Item` |
| `config.models.fetch_log` | `:fetch_log` | `SourceMonitor::FetchLog` |
| `config.models.scrape_log` | `:scrape_log` | `SourceMonitor::ScrapeLog` |
| `config.models.health_check_log` | `:health_check_log` | `SourceMonitor::HealthCheckLog` |
| `config.models.item_content` | `:item_content` | `SourceMonitor::ItemContent` |
| `config.models.log_entry` | `:log_entry` | `SourceMonitor::LogEntry` |

Each accessor returns a `ModelDefinition` with:

| Method | Signature | Description |
|---|---|---|
| `include_concern` | `(concern=nil, &block)` | Include a concern module |
| `validate` | `(handler=nil, **options, &block)` | Register a validation |

```ruby
config.models.table_name_prefix = "sm_"
config.models.source.include_concern "MyApp::SourceTagging"
config.models.item.validate :check_content_length
```

---

## Realtime Settings (`config.realtime`)

Class: `SourceMonitor::Configuration::RealtimeSettings`

| Setting | Type | Default | Description |
|---|---|---|---|
| `adapter` | Symbol | `:solid_cable` | One of `:solid_cable`, `:redis`, `:async` |
| `redis_url` | String/nil | `nil` | Redis URL when using `:redis` adapter |

### Solid Cable Options (`config.realtime.solid_cable`)

| Setting | Type | Default | Description |
|---|---|---|---|
| `polling_interval` | String | `"0.1.seconds"` | Polling frequency |
| `message_retention` | String | `"1.day"` | How long to retain messages |
| `autotrim` | Boolean | `true` | Auto-trim old messages |
| `silence_polling` | Boolean | `true` | Suppress polling log noise |
| `use_skip_locked` | Boolean | `true` | Use PostgreSQL SKIP LOCKED |
| `trim_batch_size` | Integer/nil | `nil` | Batch size for trim operations |
| `connects_to` | Hash/nil | `nil` | Multi-database routing |

### Methods

| Method | Returns | Description |
|---|---|---|
| `action_cable_config` | Hash | Full configuration hash for cable.yml |

```ruby
config.realtime.adapter = :redis
config.realtime.redis_url = "redis://localhost:6379/1"

# Or with Solid Cable tuning:
config.realtime.adapter = :solid_cable
config.realtime.solid_cable.polling_interval = "0.05.seconds"
config.realtime.solid_cable.connects_to = { database: { writing: :cable } }
```

---

## Authentication Settings (`config.authentication`)

Class: `SourceMonitor::Configuration::AuthenticationSettings`

| Setting | Type | Default | Description |
|---|---|---|---|
| `current_user_method` | Symbol/nil | `nil` | Controller method to get current user |
| `user_signed_in_method` | Symbol/nil | `nil` | Controller method to check sign-in status |

### Methods

| Method | Signature | Description |
|---|---|---|
| `authenticate_with` | `(handler=nil, &block)` | Set authentication handler |
| `authorize_with` | `(handler=nil, &block)` | Set authorization handler |

Handlers can be:
- **Symbol**: Invoked as `controller.public_send(handler)`
- **Callable**: Called with `callable.call(controller)` (or `instance_exec` if arity is 0)

```ruby
# Symbol handler (Devise)
config.authentication.authenticate_with :authenticate_user!

# Callable handler
config.authentication.authorize_with ->(controller) {
  controller.current_user&.feature_enabled?(:source_monitor)
}

# Block handler (instance_exec on controller)
config.authentication.authorize_with do
  redirect_to root_path unless current_user&.admin?
end
```

---

## Images Settings (`config.images`)

Class: `SourceMonitor::Configuration::ImagesSettings`

Controls background downloading of inline images from feed content to Active Storage.

**Prerequisite:** The host app must have Active Storage installed (`rails active_storage:install` + migrations).

| Setting | Type | Default | Description |
|---|---|---|---|
| `download_to_active_storage` | Boolean | `false` | Enable background image downloading for new items |
| `max_download_size` | Integer | `10485760` (10 MB) | Maximum image file size in bytes; larger images are skipped |
| `download_timeout` | Integer | `30` | HTTP timeout for image downloads in seconds |
| `allowed_content_types` | Array | `["image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml"]` | Permitted MIME types for downloaded images |

### Helper Method

| Method | Returns | Description |
|---|---|---|
| `download_enabled?` | Boolean | Returns `true` when `download_to_active_storage` is truthy |

```ruby
# Enable image downloading with custom limits
config.images.download_to_active_storage = true
config.images.max_download_size = 5 * 1024 * 1024  # 5 MB
config.images.download_timeout = 15
config.images.allowed_content_types = %w[image/jpeg image/png image/webp]
```

When enabled, `DownloadContentImagesJob` is automatically enqueued after new items are created from feed entries. The job downloads inline `<img>` images from `item.content`, attaches them to `item_content.images` via Active Storage, and rewrites the HTML with Active Storage serving URLs. Failed downloads gracefully preserve the original image URL.

---

## Favicons Settings (`config.favicons`)

Class: `SourceMonitor::Configuration::FaviconsSettings`

Controls automatic favicon fetching and storage for sources via Active Storage.

**Prerequisite:** The host app must have Active Storage installed (`rails active_storage:install` + migrations). Without Active Storage, favicons are silently disabled and colored initials placeholders are shown instead.

| Setting | Type | Default | Description |
|---|---|---|---|
| `enabled` | Boolean | `true` | Enable automatic favicon fetching |
| `fetch_timeout` | Integer | `5` | HTTP timeout for favicon requests (seconds) |
| `max_download_size` | Integer | `1048576` (1 MB) | Maximum favicon file size in bytes; larger files are skipped |
| `retry_cooldown_days` | Integer | `7` | Days to wait before retrying a failed favicon fetch |
| `allowed_content_types` | Array | `["image/x-icon", "image/vnd.microsoft.icon", "image/png", "image/jpeg", "image/gif", "image/svg+xml", "image/webp"]` | Permitted MIME types for downloaded favicons |

### Helper Method

| Method | Returns | Description |
|---|---|---|
| `enabled?` | Boolean | Returns `true` when `enabled` is truthy AND `ActiveStorage` is defined |

```ruby
# Customize favicon settings
config.favicons.enabled = true
config.favicons.fetch_timeout = 10
config.favicons.max_download_size = 512 * 1024  # 512 KB
config.favicons.retry_cooldown_days = 14
config.favicons.allowed_content_types = %w[image/png image/x-icon image/svg+xml]
```

When enabled, `FaviconFetchJob` is automatically enqueued:
1. After a new source is created (via UI or OPML import) with a `website_url`
2. After a successful feed fetch when the source has no favicon attached and is outside the retry cooldown

The job uses `Favicons::Discoverer` which tries three strategies in order:
1. Direct `/favicon.ico` fetch from the source's domain
2. HTML page parsing for `<link rel="icon">`, `<link rel="apple-touch-icon">`, and similar tags (prefers largest by `sizes` attribute)
3. Google Favicon API as a last resort

Failed attempts are tracked in the source's `metadata` JSONB column (`favicon_last_attempted_at`) to respect the cooldown period.

---

## Environment Variables

| Variable | Purpose |
|---|---|
| `SOLID_QUEUE_SKIP_RECURRING` | Skip loading `config/recurring.yml` |
| `SOLID_QUEUE_RECURRING_SCHEDULE_FILE` | Alternative schedule file path |
| `SOFT_DELETE` | Override retention strategy in rake tasks |
| `SOURCE_IDS` / `SOURCE_ID` | Scope cleanup rake tasks to specific sources |
| `FETCH_LOG_DAYS` / `SCRAPE_LOG_DAYS` | Retention windows for log cleanup |
| `WINDOW_MINUTES` | Time window for `stagger_fetch_times` rake task (default `10`) |
| `SOURCE_MONITOR_FETCH_CONCURRENCY` | Override fetch queue concurrency in `solid_queue.yml` |
| `SOURCE_MONITOR_SCRAPE_CONCURRENCY` | Override scrape queue concurrency in `solid_queue.yml` |
| `SOURCE_MONITOR_MAINTENANCE_CONCURRENCY` | Override maintenance queue concurrency in `solid_queue.yml` |
| `SOURCE_MONITOR_SETUP_TELEMETRY` | Enable setup verification telemetry logging |
