# FeedFetcher Architecture

## Module Structure

The `FeedFetcher` was refactored from a 627-line monolith into a 285-line coordinator with 3 sub-modules. Each sub-module is a plain Ruby class instantiated lazily via accessor methods.

```
FeedFetcher (285 lines) -- coordinator
  |
  +-- AdaptiveInterval (141 lines) -- fetch interval math
  +-- SourceUpdater (200 lines) -- source persistence + fetch logs
  +-- EntryProcessor (89 lines) -- feed entry iteration
```

## FeedFetcher (Coordinator)

**File:** `lib/source_monitor/fetching/feed_fetcher.rb`

Responsibilities:
- Perform HTTP request via Faraday client
- Route response by status code (200, 304, else)
- Parse feed body with Feedjira
- Delegate to sub-modules for processing
- Emit instrumentation events
- Handle and classify errors

### Key Data Structures

```ruby
Result = Struct.new(:status, :feed, :response, :body, :error, :item_processing, :retry_decision)
EntryProcessingResult = Struct.new(:created, :updated, :failed, :items, :errors, :created_items, :updated_items)
ResponseWrapper = Struct.new(:status, :headers, :body)
```

### Request Flow

```
call()
  -> perform_fetch(started_at, payload)
     -> perform_request()           # Faraday GET with conditional headers
     -> handle_response(response)
        |
        +-- 200 -> handle_success()
        |          -> parse_feed()          # Feedjira.parse
        |          -> entry_processor.process_feed_entries()
        |          -> source_updater.update_source_for_success()
        |          -> source_updater.create_fetch_log()
        |
        +-- 304 -> handle_not_modified()
        |          -> source_updater.update_source_for_not_modified()
        |          -> source_updater.create_fetch_log()
        |
        +-- else -> raise HTTPError
  rescue FetchError -> handle_failure()
     -> source_updater.update_source_for_failure()
     -> source_updater.create_fetch_log()
```

### Conditional Request Headers

The fetcher sends conditional headers when available:
- `If-None-Match` -- uses `source.etag`
- `If-Modified-Since` -- uses `source.last_modified.httpdate`
- Custom headers from `source.custom_headers`

### Sub-Module Instantiation

Sub-modules are lazily instantiated and cached:

```ruby
def adaptive_interval
  @adaptive_interval ||= AdaptiveInterval.new(source: source, jitter_proc: jitter_proc)
end

def source_updater
  @source_updater ||= SourceUpdater.new(source: source, adaptive_interval: adaptive_interval)
end

def entry_processor
  @entry_processor ||= EntryProcessor.new(source: source)
end
```

### Backward Compatibility

Forwarding methods maintain backward compatibility with existing tests:

```ruby
def process_feed_entries(feed) = entry_processor.process_feed_entries(feed)
def jitter_offset(interval_seconds) = adaptive_interval.jitter_offset(interval_seconds)
# ... etc
```

## AdaptiveInterval Sub-Module

**File:** `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb`

Controls dynamic fetch scheduling based on content changes and failures.

### Algorithm

| Condition | Factor | Effect |
|-----------|--------|--------|
| Content changed | `DECREASE_FACTOR` (0.75) | Fetch more often |
| No change | `INCREASE_FACTOR` (1.25) | Fetch less often |
| Failure | `FAILURE_INCREASE_FACTOR` (1.5) | Back off significantly |

### Boundaries

| Constant | Default | Purpose |
|----------|---------|---------|
| `MIN_FETCH_INTERVAL` | 5 minutes | Floor for interval |
| `MAX_FETCH_INTERVAL` | 24 hours | Ceiling for interval |
| `JITTER_PERCENT` | 10% | Random offset to prevent thundering herd |

### Configuration Override

All constants can be overridden via `SourceMonitor.config.fetching`:
- `min_interval_minutes`
- `max_interval_minutes`
- `increase_factor`
- `decrease_factor`
- `failure_increase_factor`
- `jitter_percent`

### Fixed vs Adaptive

When `source.adaptive_fetching_enabled?` is false, the interval uses a simple fixed schedule:

```ruby
fixed_minutes = [source.fetch_interval_minutes.to_i, 1].max
attributes[:next_fetch_at] = Time.current + fixed_minutes.minutes
```

## SourceUpdater Sub-Module

**File:** `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

Handles all source record mutations after a fetch attempt.

### Update Methods

| Method | When Called | Key Updates |
|--------|------------|-------------|
| `update_source_for_success` | HTTP 200 | Clear errors, update etag/last_modified, adaptive interval, reset retry state |
| `update_source_for_not_modified` | HTTP 304 | Clear errors, update etag/last_modified, adaptive interval |
| `update_source_for_failure` | Any error | Increment failure_count, apply retry strategy, adaptive interval with failure flag |

### Fetch Log Creation

Every fetch attempt creates a `FetchLog` record via `create_fetch_log` with:
- Timing (started_at, completed_at, duration_ms)
- HTTP details (status, response headers)
- Item counts (created, updated, failed)
- Error details (class, message, backtrace)
- Feed metadata (parser, signature, item errors)

### Feed Signature

Content change detection uses SHA256 digest of the response body:

```ruby
def feed_signature_changed?(feed_signature)
  (source.metadata || {}).fetch("last_feed_signature", nil) != feed_signature
end
```

### Retry Strategy

On failure, `apply_retry_strategy!` delegates to `RetryPolicy`:
- If retry: set `fetch_retry_attempt`, schedule retry
- If circuit open: set `fetch_circuit_opened_at`, `fetch_circuit_until`
- Updates `next_fetch_at` and `backoff_until` accordingly

## EntryProcessor Sub-Module

**File:** `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb`

Iterates over `feed.entries` and calls `ItemCreator.call` for each entry.

### Processing Loop

```ruby
Array(feed.entries).each do |entry|
  result = ItemCreator.call(source:, entry:)
  Events.run_item_processors(source:, entry:, result:)
  if result.created?
    Events.after_item_created(item: result.item, source:, entry:, result:)
  end
rescue StandardError => error
  # Normalize error, continue processing remaining entries
end
```

Key behaviors:
- Individual entry failures don't stop processing of remaining entries
- Events are dispatched for both item processors and item creation
- Error normalization captures GUID and title for debugging
