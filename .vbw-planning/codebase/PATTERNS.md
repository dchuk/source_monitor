# Patterns

Recurring patterns observed across the SourceMonitor codebase.

## 1. Service Object Pattern

**Where**: `lib/source_monitor/fetching/`, `lib/source_monitor/scraping/`, `lib/source_monitor/health/`, `lib/source_monitor/items/`

Service objects encapsulate domain operations. They follow a consistent structure:

```ruby
class SomeService
  def initialize(source:, **deps)
    @source = source
  end

  def call
    # orchestrate operation
    # return a Result struct
  end
end
```

**Examples**:
- `Fetching::FeedFetcher` -- `#call` returns `Result` struct
- `Scraping::ItemScraper` -- `#call` returns `Result` struct
- `Health::SourceHealthMonitor` -- `#call` updates source health
- `Health::SourceHealthCheck` -- `#call` probes source URL
- `Items::RetentionPruner` -- `#call` prunes old items
- `Items::ItemCreator` -- `.call(source:, entry:)` class method

## 2. Struct-Based Result Objects

**Where**: Throughout all service objects

Operations return typed `Struct` instances rather than raw hashes or arrays:

```ruby
Result = Struct.new(:status, :item, :log, :message, :error, keyword_init: true) do
  def success?
    status.to_s != "failed"
  end
end
```

**Examples**:
- `Scraping::ItemScraper::Result` -- `:status, :item, :log, :message, :error`
- `Scrapers::Base::Result` -- `:status, :html, :content, :metadata`
- `Fetching::FeedFetcher::Result` -- `:status, :feed, :response, :body, :error, :item_processing, :retry_decision`
- `Fetching::FeedFetcher::EntryProcessingResult` -- `:created, :updated, :failed, :items, :errors`
- `Events::ItemCreatedEvent`, `Events::ItemScrapedEvent`, `Events::FetchCompletedEvent`
- `Setup::Verification::Result` -- verification outcome

## 3. Adapter/Strategy Pattern

**Where**: `lib/source_monitor/scrapers/`, `lib/source_monitor/realtime/`, `lib/source_monitor/items/retention_strategies/`

Pluggable behavior via abstract base class with `#call` contract:

```ruby
class Scrapers::Base
  def call
    raise NotImplementedError
  end
end
```

**Instances**:
- **Scraper adapters**: `Scrapers::Base` -> `Scrapers::Readability` (registered in `ScraperRegistry`)
- **Realtime adapters**: `solid_cable`, `redis`, `async` (configured in `RealtimeSettings`)
- **Retention strategies**: `:destroy`, `:soft_delete` (in `Items::RetentionStrategies/`)

## 4. Event/Callback System

**Where**: `lib/source_monitor/events.rb`, `lib/source_monitor/configuration.rb`

Event-driven communication between engine components:

```ruby
# Registration
SourceMonitor.config.events.after_item_created { |event| ... }
SourceMonitor.config.events.after_item_scraped { |event| ... }
SourceMonitor.config.events.after_fetch_completed { |event| ... }

# Dispatch
SourceMonitor::Events.after_item_created(item:, source:, entry:, result:)
```

- Typed event structs carry context
- Error isolation: each handler failure is logged, does not stop other handlers
- Item processor pipeline: `Events.run_item_processors` runs all registered processors
- Used by `Health` module to register fetch completion callback

## 5. Configuration DSL with Nested Settings Objects

**Where**: `lib/source_monitor/configuration.rb`

Deeply nested configuration with domain-specific settings classes:

```ruby
SourceMonitor.configure do |config|
  config.http.timeout = 30
  config.fetching.min_interval_minutes = 10
  config.health.window_size = 50
  config.scrapers.register(:custom, MyCustomScraper)
  config.models.source.include_concern SomeConcern
  config.authentication.authenticate_with :authenticate_admin!
end
```

**Pattern traits**:
- Each settings class has `reset!` for test isolation
- Constants for defaults (e.g., `DEFAULT_QUEUE_NAMESPACE`)
- Callable values supported (procs/lambdas) for dynamic resolution
- Validation in setters (e.g., `RealtimeSettings#adapter=` checks `VALID_ADAPTERS`)

## 6. Model Extension System

**Where**: `lib/source_monitor/model_extensions.rb`, `lib/source_monitor/configuration.rb`

Host apps can dynamically inject concerns and validations into engine models:

```ruby
config.models.source.include_concern "MyApp::SourceExtensions"
config.models.source.validate :custom_validator
config.models.source.validate { |record| record.errors.add(:base, "invalid") if ... }
```

- `ModelExtensions.register(model_class, key)` called in each model class body
- `ModelExtensions.reload!` re-applies all extensions on configuration change
- Manages table name prefix assignment
- Tracks applied concerns/validations to prevent duplicates
- Removes old extension validations before re-applying

## 7. Turbo Stream Response Pattern

**Where**: `lib/source_monitor/turbo_streams/stream_responder.rb`, controllers

Controllers build Turbo Stream responses via a `StreamResponder` builder:

```ruby
responder = SourceMonitor::TurboStreams::StreamResponder.new
presenter = SourceMonitor::Sources::TurboStreamPresenter.new(source:, responder:)
presenter.render_deletion(metrics:, query:, ...)
responder.toast(message:, level: :success)
render turbo_stream: responder.render(view_context)
```

- Accumulates stream actions as an array
- Supports toast notifications, redirects, and custom actions
- Pairs with Stimulus controllers on the frontend

## 8. Defensive Logging Guard

**Where**: All jobs and service objects

Consistent pattern for safe logging:

```ruby
def log(stage, **extra)
  return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
  Rails.logger.info("[SourceMonitor::...] #{payload.to_json}")
rescue StandardError
  nil
end
```

This three-part guard (`defined?`, `respond_to?`, truthy check) prevents errors when running outside Rails (e.g., in tests or standalone scripts).

## 9. ActiveSupport::Notifications Instrumentation

**Where**: `lib/source_monitor/instrumentation.rb`, `lib/source_monitor/metrics.rb`

Standard Rails instrumentation pattern:

```ruby
# Emit events
SourceMonitor::Instrumentation.fetch_start(payload)
SourceMonitor::Instrumentation.fetch_finish(payload)

# Subscribe to events
ActiveSupport::Notifications.subscribe("source_monitor.fetch.finish") do |...|
  SourceMonitor::Metrics.increment(:fetch_finished_total)
end
```

- Events namespaced as `source_monitor.*`
- Monotonic clock for duration measurement
- Metrics module aggregates counters and gauges in memory

## 10. Search/Filter with Ransack

**Where**: Models (`ransackable_attributes`, `ransackable_associations`), `SanitizesSearchParams` concern

```ruby
class Source < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[name feed_url website_url created_at ...]
  end
end
```

- Explicit whitelisting of searchable attributes (required by Ransack 4+)
- `SanitizesSearchParams` controller concern sanitizes search inputs
- Used in `SourcesController#index` and `LogsController#index`

## 11. Circuit Breaker / Retry Policy

**Where**: `lib/source_monitor/fetching/retry_policy.rb`, `lib/source_monitor/fetching/feed_fetcher.rb`, `app/jobs/source_monitor/fetch_feed_job.rb`

Fetch failures trigger an escalating retry policy:

1. **Retry with backoff**: Exponential wait, up to N attempts
2. **Circuit open**: After exhausting retries, block fetches for a cooldown period
3. **Circuit close**: Scheduler recovers after cooldown expires

State stored on `Source` model: `fetch_retry_attempt`, `fetch_circuit_opened_at`, `fetch_circuit_until`, `backoff_until`.

## 12. Wizard State Machine (OPML Import)

**Where**: `app/models/source_monitor/import_session.rb`, `app/controllers/source_monitor/import_sessions_controller.rb`

Multi-step wizard with explicit step ordering:

```ruby
STEP_ORDER = %w[upload preview health_check configure confirm].freeze
```

- State persisted in `ImportSession` model with JSONB columns
- Each step has dedicated `handle_*_step` and `prepare_*_context` methods
- Navigation via `next_step`/`previous_step` model methods
- Step transitions guarded by validation (e.g., "select at least one source")

## 13. Soft Delete Pattern

**Where**: `app/models/source_monitor/item.rb`

Items use soft deletion via `deleted_at` timestamp rather than physical deletion:

```ruby
scope :active, -> { where(deleted_at: nil) }
scope :with_deleted, -> { unscope(where: :deleted_at) }
scope :only_deleted, -> { where.not(deleted_at: nil) }

def soft_delete!(timestamp: Time.current)
  update_columns(deleted_at: timestamp, updated_at: timestamp)
  Source.decrement_counter(:items_count, source_id)
end
```

No `default_scope` is used (explicitly noted as avoiding anti-pattern).

## 14. Separate Content Table

**Where**: `app/models/source_monitor/item.rb`, `app/models/source_monitor/item_content.rb`

Large scraped content is stored in a separate `ItemContent` model rather than on the `Item` directly:

- Lazy-loaded via `has_one :item_content`
- Auto-created when content is assigned, auto-destroyed when both fields become blank
- Delegates `scraped_html` and `scraped_content` to `ItemContent`
- Prevents bloating the items table with large text columns
