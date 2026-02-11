# Configuration Settings Catalog

All configuration sections with their attributes, defaults, and types.

## Top-Level Attributes

**File:** `lib/source_monitor/configuration.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `queue_namespace` | String | `"source_monitor"` | Namespace prefix for queue names |
| `fetch_queue_name` | String | `"source_monitor_fetch"` | Queue name for fetch jobs |
| `scrape_queue_name` | String | `"source_monitor_scrape"` | Queue name for scrape jobs |
| `fetch_queue_concurrency` | Integer | `2` | Max concurrent fetch workers |
| `scrape_queue_concurrency` | Integer | `2` | Max concurrent scrape workers |
| `recurring_command_job_class` | Class/nil | `nil` | Custom recurring job class |
| `job_metrics_enabled` | Boolean | `true` | Enable job metrics tracking |
| `mission_control_enabled` | Boolean | `false` | Enable Mission Control integration |
| `mission_control_dashboard_path` | String/Proc/nil | `nil` | Path or callable for Mission Control |

**Methods:**
- `queue_name_for(:fetch)` / `queue_name_for(:scrape)` -- Returns prefixed queue name
- `concurrency_for(:fetch)` / `concurrency_for(:scrape)` -- Returns concurrency limit

---

## HTTPSettings

**File:** `lib/source_monitor/configuration/http_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `timeout` | Integer | `15` | Total request timeout (seconds) |
| `open_timeout` | Integer | `5` | Connection open timeout (seconds) |
| `max_redirects` | Integer | `5` | Max HTTP redirects to follow |
| `user_agent` | String | `"SourceMonitor/<version>"` | User-Agent header value |
| `proxy` | String/nil | `nil` | HTTP proxy URL |
| `headers` | Hash | `{}` | Default HTTP headers |
| `retry_max` | Integer | `4` | Max retry attempts |
| `retry_interval` | Float | `0.5` | Base retry interval (seconds) |
| `retry_interval_randomness` | Float | `0.5` | Retry interval randomness factor |
| `retry_backoff_factor` | Integer | `2` | Exponential backoff multiplier |
| `retry_statuses` | Array/nil | `nil` | HTTP statuses to retry on |

Has `reset!` method.

---

## FetchingSettings

**File:** `lib/source_monitor/configuration/fetching_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `min_interval_minutes` | Integer | `5` | Minimum fetch interval |
| `max_interval_minutes` | Integer | `1440` (24h) | Maximum fetch interval |
| `increase_factor` | Float | `1.25` | Multiplier when content unchanged |
| `decrease_factor` | Float | `0.75` | Multiplier when content changed |
| `failure_increase_factor` | Float | `1.5` | Multiplier on fetch failure |
| `jitter_percent` | Float | `0.1` | Random jitter (10%) |

Has `reset!` method. All attributes are plain `attr_accessor`.

---

## HealthSettings

**File:** `lib/source_monitor/configuration/health_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `window_size` | Integer | `20` | Rolling window of fetches for health calc |
| `healthy_threshold` | Float | `0.8` | Success rate above = healthy |
| `warning_threshold` | Float | `0.5` | Success rate above = warning |
| `auto_pause_threshold` | Float | `0.2` | Success rate below = auto-pause |
| `auto_resume_threshold` | Float | `0.6` | Success rate above = auto-resume |
| `auto_pause_cooldown_minutes` | Integer | `60` | Cooldown before auto-resume check |

Has `reset!` method. All attributes are plain `attr_accessor`.

---

## ScrapingSettings

**File:** `lib/source_monitor/configuration/scraping_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_in_flight_per_source` | Integer/nil | `25` | Max concurrent scrape jobs per source |
| `max_bulk_batch_size` | Integer/nil | `100` | Max items in a bulk scrape batch |

Has `reset!` method. Custom setters normalize values:
- `nil` -> `nil`
- `""` -> `nil`
- `0` or negative -> `nil`
- String -> parsed integer (if positive)
- Positive integer -> kept as-is

---

## RetentionSettings

**File:** `lib/source_monitor/configuration/retention_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `items_retention_days` | Integer/nil | `nil` | Days to keep items (nil = forever) |
| `max_items` | Integer/nil | `nil` | Max items per source (nil = unlimited) |
| `strategy` | Symbol | `:destroy` | `:destroy` or `:soft_delete` |

No `reset!` method (defaults set in `initialize`). The `strategy=` setter validates against allowed values and raises `ArgumentError` for invalid input. Setting `nil` resets to `:destroy`.

---

## RealtimeSettings

**File:** `lib/source_monitor/configuration/realtime_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `adapter` | Symbol | `:solid_cable` | One of `:solid_cable`, `:redis`, `:async` |
| `redis_url` | String/nil | `nil` | Redis URL (for `:redis` adapter) |
| `solid_cable` | SolidCableOptions | (nested object) | Solid Cable options |

Has `reset!` method. The `adapter=` setter validates against `VALID_ADAPTERS`.

**SolidCableOptions:**

| Attribute | Type | Default |
|-----------|------|---------|
| `polling_interval` | String | `"0.1.seconds"` |
| `message_retention` | String | `"1.day"` |
| `autotrim` | Boolean | `true` |
| `silence_polling` | Boolean | `true` |
| `use_skip_locked` | Boolean | `true` |
| `trim_batch_size` | Integer/nil | `nil` |
| `connects_to` | Hash/nil | `nil` |

**Methods:**
- `action_cable_config` -- Returns hash suitable for ActionCable configuration
- `solid_cable=(hash)` -- Bulk-assign SolidCable options from a hash

---

## AuthenticationSettings

**File:** `lib/source_monitor/configuration/authentication_settings.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `authenticate_handler` | Handler/nil | `nil` | Authentication handler |
| `authorize_handler` | Handler/nil | `nil` | Authorization handler |
| `current_user_method` | Symbol/nil | `nil` | Method name for current user |
| `user_signed_in_method` | Symbol/nil | `nil` | Method name for signed-in check |

Has `reset!` method.

**Methods:**
- `authenticate_with(handler = nil, &block)` -- Register authentication handler
- `authorize_with(handler = nil, &block)` -- Register authorization handler

Handler types: `:symbol` (method name), `:callable` (lambda/proc/block).

---

## Events

**File:** `lib/source_monitor/configuration/events.rb`

| Callback Key | Description |
|-------------|-------------|
| `after_item_created` | Fires after a new item is created from a feed entry |
| `after_item_scraped` | Fires after an item's content is scraped |
| `after_fetch_completed` | Fires after a feed fetch completes (success or failure) |

**Methods:**
- `after_item_created(handler = nil, &block)` -- Register callback
- `after_item_scraped(handler = nil, &block)` -- Register callback
- `after_fetch_completed(handler = nil, &block)` -- Register callback
- `register_item_processor(processor = nil, &block)` -- Register item processor
- `callbacks_for(name)` -- Returns array of callbacks (dup'd)
- `item_processors` -- Returns array of processors (dup'd)
- `reset!` -- Clears all callbacks and processors

All handlers must respond to `#call`. Raises `ArgumentError` otherwise.

---

## ScraperRegistry

**File:** `lib/source_monitor/configuration/scraper_registry.rb`

Enumerable registry of scraper adapters.

**Methods:**
- `register(name, adapter)` -- Register adapter class by name
- `unregister(name)` -- Remove adapter
- `adapter_for(name)` -- Look up adapter class by name
- `each` -- Iterate over `{name => adapter}` pairs

Names are normalized to lowercase alphanumeric + underscores. Adapter classes must inherit from `SourceMonitor::Scrapers::Base`.

---

## Models

**File:** `lib/source_monitor/configuration/models.rb`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `table_name_prefix` | String | `"sourcemon_"` | Database table prefix |

**Model Keys:** `source`, `item`, `fetch_log`, `scrape_log`, `health_check_log`, `item_content`, `log_entry`

Each key returns a `ModelDefinition` instance.

**Methods:**
- `for(name)` -- Returns `ModelDefinition` by name (raises on unknown)

---

## ModelDefinition

**File:** `lib/source_monitor/configuration/model_definition.rb`

**Methods:**
- `include_concern(concern = nil, &block)` -- Register a concern module
- `each_concern` -- Iterate over registered concerns (yields `[signature, resolved_module]`)
- `validate(handler = nil, **options, &block)` -- Register a custom validation
- `validations` -- Returns array of `ValidationDefinition` instances

Concerns can be: Module instance, String constant name, or anonymous block.
Validations can be: Symbol method name, String, lambda, or block.

---

## ValidationDefinition

**File:** `lib/source_monitor/configuration/validation_definition.rb`

| Attribute | Type | Description |
|-----------|------|-------------|
| `handler` | Symbol/Proc | The validation handler |
| `options` | Hash | Options hash (e.g., `{ if: :active? }`) |

**Methods:**
- `signature` -- Returns deduplication key
- `symbol?` -- Returns true if handler is a Symbol or String
