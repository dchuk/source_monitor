# Job Conventions Reference

## ApplicationJob Base Class

All engine jobs inherit from `SourceMonitor::ApplicationJob`:

```ruby
# app/jobs/source_monitor/application_job.rb
module SourceMonitor
  parent_job = defined?(::ApplicationJob) ? ::ApplicationJob : ActiveJob::Base

  class ApplicationJob < parent_job
    class << self
      def source_monitor_queue(role)
        queue_as SourceMonitor.queue_name(role)
      end
    end
  end
end
```

Key behaviors:
- Inherits from host app's `ApplicationJob` if available, otherwise `ActiveJob::Base`
- Provides `source_monitor_queue` class method for engine-aware queue naming
- Host app job middleware (logging, error tracking) applies automatically

## Queue Naming

### Configuration Chain

```
SourceMonitor.queue_name(:fetch)
  -> config.queue_name_for(:fetch)
     -> config.fetch_queue_name  # "source_monitor_fetch"
     -> prepend ActiveJob::Base.queue_name_prefix if set
```

### Default Names

| Role | Queue Name |
|------|-----------|
| `:fetch` | `source_monitor_fetch` |
| `:scrape` | `source_monitor_scrape` |

### With Host App Prefix

If the host app sets `ActiveJob::Base.queue_name_prefix = "myapp"`:
- Fetch queue becomes `myapp_source_monitor_fetch`
- Scrape queue becomes `myapp_source_monitor_scrape`

## Job Patterns by Type

### Fetch Job (FetchFeedJob)

The most complex job, demonstrating retry strategy integration:

```ruby
class FetchFeedJob < ApplicationJob
  FETCH_CONCURRENCY_RETRY_WAIT = 30.seconds
  EARLY_EXECUTION_LEEWAY = 30.seconds

  source_monitor_queue :fetch

  discard_on ActiveJob::DeserializationError
  retry_on FetchRunner::ConcurrencyError, wait: 30.seconds, attempts: 5

  def perform(source_id, force: false)
    source = Source.find_by(id: source_id)
    return unless source
    return unless should_run?(source, force: force)
    FetchRunner.new(source: source, force: force).run
  rescue FetchError => error
    handle_transient_error(source, error)
  end
end
```

Notable patterns:
- `should_run?` guard prevents premature execution
- `ConcurrencyError` uses ActiveJob `retry_on` (another worker holds the lock)
- `FetchError` uses custom retry logic via `RetryPolicy`
- `force: false` keyword argument for manual vs scheduled fetches

### Cleanup Job (ItemCleanupJob)

Demonstrates options normalization pattern:

```ruby
class ItemCleanupJob < ApplicationJob
  DEFAULT_BATCH_SIZE = 100
  source_monitor_queue :fetch

  def perform(options = nil)
    options = Jobs::CleanupOptions.normalize(options)
    scope = resolve_scope(options)
    batch_size = Jobs::CleanupOptions.batch_size(options, default: DEFAULT_BATCH_SIZE)
    now = Jobs::CleanupOptions.resolve_time(options[:now])
    strategy = resolve_strategy(options)

    scope.find_in_batches(batch_size:) do |batch|
      batch.each { |source| RetentionPruner.call(source:, now:, strategy:) }
    end
  end
end
```

Notable patterns:
- Accepts flexible `options` hash (works with both manual and recurring invocation)
- Uses `CleanupOptions` helper for safe normalization
- Batched processing with configurable batch size

### Worker Job (ScrapeItemJob)

Demonstrates lifecycle logging:

```ruby
class ScrapeItemJob < ApplicationJob
  source_monitor_queue :scrape
  discard_on ActiveJob::DeserializationError

  def perform(item_id)
    log("job:start", item_id: item_id)
    item = Item.includes(:source).find_by(id: item_id)
    return unless item

    source = item.source
    unless source&.scraping_enabled?
      log("job:skipped_scraping_disabled", item: item)
      Scraping::State.clear_inflight!(item)
      return
    end

    Scraping::State.mark_processing!(item)
    Scraping::ItemScraper.new(item:, source:).call
    log("job:completed", item: item, status: item.scrape_status)
  rescue StandardError => error
    log("job:error", item: item, error: error.message)
    Scraping::State.mark_failed!(item)
    raise
  ensure
    Scraping::State.clear_inflight!(item) if item
  end
end
```

Notable patterns:
- `includes(:source)` prevents N+1 query
- Lifecycle state management (`mark_processing!`, `clear_inflight!`)
- Error re-raise after state cleanup
- Structured JSON logging at each stage

### Scheduling Job (ScheduleFetchesJob)

Simplest pattern -- pure delegation:

```ruby
class ScheduleFetchesJob < ApplicationJob
  source_monitor_queue :fetch

  def perform(options = nil)
    limit = extract_limit(options)
    Scheduler.run(limit:)
  end
end
```

### Lightweight Fetch Job (FaviconFetchJob)

Demonstrates multi-strategy cascade with guard clauses:

```ruby
class FaviconFetchJob < ApplicationJob
  source_monitor_queue :fetch
  discard_on ActiveJob::DeserializationError

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source
    return unless should_fetch?(source)

    result = Favicons::Discoverer.new(source: source).call
    attach_favicon(source, result) if result.success?
  end
end
```

Notable patterns:
- Multiple guard clauses: source exists, Active Storage defined, no existing favicon, outside cooldown period
- Uses `Favicons::Discoverer` service with 3-strategy cascade (direct `/favicon.ico`, HTML parsing, Google API)
- Failed attempts tracked in source `metadata` JSONB (`favicon_last_attempted_at`) for retry cooldown
- Graceful degradation: host apps without Active Storage never enqueue this job

### Broadcast Job (SourceHealthCheckJob)

Demonstrates result broadcasting:

```ruby
class SourceHealthCheckJob < ApplicationJob
  source_monitor_queue :fetch
  discard_on ActiveJob::DeserializationError

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source

    result = Health::SourceHealthCheck.new(source: source).call
    broadcast_outcome(source, result)
    result
  rescue StandardError => error
    record_unexpected_failure(source, error) if source
    broadcast_outcome(source, nil, error) if source
    nil
  end
end
```

Notable patterns:
- Always broadcasts UI update (success or failure)
- Creates log record even for unexpected failures
- Returns nil on error instead of re-raising (health checks are non-critical)

## _later / _now Naming Convention

Models and services should expose `_later` methods for async work:

```ruby
# On the model or service
def self.fetch_later(source_or_id, force: false)
  FetchRunner.enqueue(source_or_id, force: force)
end

def self.fetch_now(source, force: false)
  FetchRunner.run(source: source, force: force)
end
```

Jobs are the mechanism, not the API. Callers should use model/service methods, not enqueue jobs directly.

## Job Support Classes

### CleanupOptions

**File:** `lib/source_monitor/jobs/cleanup_options.rb`

Normalizes job arguments for cleanup jobs:

| Method | Purpose |
|--------|---------|
| `normalize(options)` | Symbolize keys, handle nil/non-Hash |
| `resolve_time(value)` | Parse Time/String/nil to Time |
| `extract_ids(value)` | Flatten arrays, split CSV, convert to integers |
| `integer(value)` | Safe Integer conversion |
| `batch_size(options, default:)` | Extract positive batch size |

### FetchFailureSubscriber

**File:** `lib/source_monitor/jobs/fetch_failure_subscriber.rb`

Subscribes to Solid Queue failure events for fetch queue jobs. Used for metrics and alerting.

### Visibility

**File:** `lib/source_monitor/jobs/visibility.rb`

Tracks queue depth and timing metrics per queue.

### SolidQueueMetrics

**File:** `lib/source_monitor/jobs/solid_queue_metrics.rb`

Queries Solid Queue tables for dashboard metrics: pending count, failed count, paused queues, oldest job age.
