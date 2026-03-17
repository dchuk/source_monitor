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

| Role | Queue Name | Jobs |
|------|-----------|------|
| `:fetch` | `source_monitor_fetch` | FetchFeedJob, ScheduleFetchesJob |
| `:scrape` | `source_monitor_scrape` | ScrapeItemJob |
| `:maintenance` | `source_monitor_maintenance` | SourceHealthCheckJob, ImportSessionHealthCheckJob, ImportOpmlJob, LogCleanupJob, ItemCleanupJob, FaviconFetchJob, DownloadContentImagesJob |

### With Host App Prefix

If the host app sets `ActiveJob::Base.queue_name_prefix = "myapp"`:
- Fetch queue becomes `myapp_source_monitor_fetch`
- Scrape queue becomes `myapp_source_monitor_scrape`
- Maintenance queue becomes `myapp_source_monitor_maintenance`

## Job Patterns by Type

### Fetch Job (FetchFeedJob)

The most complex job, demonstrating retry strategy integration:

```ruby
class FetchFeedJob < ApplicationJob
  FETCH_CONCURRENCY_BASE_WAIT = 30.seconds
  FETCH_CONCURRENCY_MAX_WAIT = 5.minutes
  EARLY_EXECUTION_LEEWAY = 30.seconds

  source_monitor_queue :fetch

  discard_on ActiveJob::DeserializationError
  # ConcurrencyError: exponential backoff (30s * 2^attempt) with 25% jitter, discards after 5 attempts

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
  source_monitor_queue :maintenance

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

Demonstrates shallow delegation to a service class:

```ruby
class ScrapeItemJob < ApplicationJob
  source_monitor_queue :scrape
  discard_on ActiveJob::DeserializationError

  def perform(item_id)
    item = Item.includes(:source).find_by(id: item_id)
    return unless item

    Scraping::Runner.new(item: item).call
  end
end
```

Notable patterns:
- Job body is deserialization + delegation only
- All business logic (state management, scraping, logging) lives in `Scraping::Runner`
- `includes(:source)` prevents N+1 query before handing off to the service

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

Demonstrates shallow delegation with guard clause:

```ruby
class FaviconFetchJob < ApplicationJob
  source_monitor_queue :maintenance
  discard_on ActiveJob::DeserializationError

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source

    Favicons::Fetcher.new(source: source).call
  end
end
```

Notable patterns:
- Job contains only lookup + delegation — guard clauses and discovery strategy cascade live in `Favicons::Fetcher`
- Graceful degradation: host apps without Active Storage never enqueue this job

### Broadcast Job (SourceHealthCheckJob)

Demonstrates shallow delegation with result broadcasting:

```ruby
class SourceHealthCheckJob < ApplicationJob
  source_monitor_queue :maintenance
  discard_on ActiveJob::DeserializationError

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source

    Health::SourceHealthCheckOrchestrator.new(source: source).call
  end
end
```

Notable patterns:
- Job body is lookup + delegation only
- Broadcasting, logging, and error handling live in `Health::SourceHealthCheckOrchestrator`
- Returns nil on missing source; orchestrator handles nil-on-error (health checks are non-critical)

## Shallow Delegation Pattern

As of v0.12.0, five maintenance jobs delegate entirely to dedicated service classes. Jobs contain only deserialization and delegation — no business logic.

| Job | Service Class |
|-----|---------------|
| `ScrapeItemJob` | `Scraping::Runner` |
| `DownloadContentImagesJob` | `Images::Processor` |
| `FaviconFetchJob` | `Favicons::Fetcher` |
| `SourceHealthCheckJob` | `Health::SourceHealthCheckOrchestrator` |
| `ImportSessionHealthCheckJob` | `ImportSessions::HealthCheckUpdater` |

**Why this pattern:**
- Jobs are the transport mechanism, not the behavior container.
- Service classes are unit-testable without ActiveJob infrastructure.
- Future pipeline changes (e.g., calling the same logic synchronously) require no job changes.

**Template for new jobs:**

```ruby
class MyJob < ApplicationJob
  source_monitor_queue :maintenance
  discard_on ActiveJob::DeserializationError

  def perform(record_id)
    record = MyModel.find_by(id: record_id)
    return unless record

    MyNamespace::MyService.new(record: record).call
  end
end
```

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
