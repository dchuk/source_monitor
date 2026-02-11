# Events API Reference

Complete reference for SourceMonitor's event system.

Source: `lib/source_monitor/events.rb` and `lib/source_monitor/configuration/events.rb`

## Registration API

All registration happens on `config.events` inside the configure block:

```ruby
SourceMonitor.configure do |config|
  config.events.after_item_created { |event| ... }
  config.events.after_item_scraped(handler)
  config.events.after_fetch_completed(MyHandler.new)
  config.events.register_item_processor(->(ctx) { ... })
end
```

### `after_item_created(handler = nil, &block)`

Register a callback for new item creation.

**Handler requirements:** Must respond to `#call`. Receives an `ItemCreatedEvent`.

**Returns:** The registered callable.

### `after_item_scraped(handler = nil, &block)`

Register a callback for item scrape completion.

**Handler requirements:** Must respond to `#call`. Receives an `ItemScrapedEvent`.

**Returns:** The registered callable.

### `after_fetch_completed(handler = nil, &block)`

Register a callback for feed fetch completion.

**Handler requirements:** Must respond to `#call`. Receives a `FetchCompletedEvent`.

**Returns:** The registered callable.

### `register_item_processor(processor = nil, &block)`

Register an item processor for post-entry processing.

**Handler requirements:** Must respond to `#call`. Receives an `ItemProcessorContext`.

**Returns:** The registered callable.

### `callbacks_for(name) -> Array`

Retrieve a copy of registered callbacks for a given event name.

### `item_processors -> Array`

Retrieve a copy of registered item processors.

### `reset!`

Clear all callbacks and item processors. Used in tests.

## Event Structs

### `ItemCreatedEvent`

Fired by `Events.after_item_created` after a new item is created from a feed entry.

```ruby
ItemCreatedEvent = Struct.new(
  :item,        # SourceMonitor::Item - the newly created item
  :source,      # SourceMonitor::Source - the owning source
  :entry,       # Object - raw feed entry from Feedjira
  :result,      # Object - creation result
  :status,      # String - result status (e.g., "created")
  :occurred_at, # Time - when the event fired
  keyword_init: true
)
```

**Helper methods:**
- `created?` -- returns `true` when `status.to_s == "created"`

**Dispatched from:** `SourceMonitor::Events.after_item_created` (called by `EntryProcessor`)

### `ItemScrapedEvent`

Fired by `Events.after_item_scraped` after content scraping completes.

```ruby
ItemScrapedEvent = Struct.new(
  :item,        # SourceMonitor::Item - the scraped item
  :source,      # SourceMonitor::Source - the owning source
  :result,      # Object - scrape result
  :log,         # SourceMonitor::ScrapeLog - the scrape log record
  :status,      # String - result status
  :occurred_at, # Time - when the event fired
  keyword_init: true
)
```

**Helper methods:**
- `success?` -- returns `true` when `status.to_s != "failed"`

**Dispatched from:** `SourceMonitor::Events.after_item_scraped` (called by `ItemScraper`)

### `FetchCompletedEvent`

Fired by `Events.after_fetch_completed` after a feed fetch finishes.

```ruby
FetchCompletedEvent = Struct.new(
  :source,      # SourceMonitor::Source - the fetched source
  :result,      # Object - fetch result
  :status,      # String - result status
  :occurred_at, # Time - when the event fired
  keyword_init: true
)
```

**Dispatched from:** `SourceMonitor::Events.after_fetch_completed` (called by `Completion::EventPublisher`)

### `ItemProcessorContext`

Passed to item processors registered via `register_item_processor`.

```ruby
ItemProcessorContext = Struct.new(
  :item,        # SourceMonitor::Item - the processed item
  :source,      # SourceMonitor::Source - the owning source
  :entry,       # Object - raw feed entry
  :result,      # Object - processing result
  :status,      # String - result status
  :occurred_at, # Time - when processing occurred
  keyword_init: true
)
```

**Dispatched from:** `SourceMonitor::Events.run_item_processors` (called by `EntryProcessor`)

## Dispatch Mechanics

### `Events.dispatch(event_name, event)`

Iterates all callbacks for the event name and calls each one:

```ruby
def dispatch(event_name, event)
  SourceMonitor.config.events.callbacks_for(event_name).each do |callback|
    invoke(callback, event)
  rescue StandardError => error
    log_handler_error(event_name, callback, error)
  end
end
```

### `Events.invoke(callable, event)`

Handles zero-arity and single-arity callables:

```ruby
def invoke(callable, event)
  if callable.respond_to?(:arity) && callable.arity.zero?
    callable.call
  else
    callable.call(event)
  end
end
```

### Error Logging

Handler errors are logged but never propagated:

```
[SourceMonitor] after_item_created handler #<Proc:0x...> failed: RuntimeError: boom
```

Logged via `Rails.logger.error` with `warn` as fallback.

## Handler Types

| Type | Example | Notes |
|---|---|---|
| Block | `after_item_created { \|e\| ... }` | Most common for simple handlers |
| Lambda | `after_item_created ->( e) { ... }` | Strict arity checking |
| Proc | `after_item_created proc { \|e\| ... }` | Relaxed arity |
| Object | `after_item_created(MyHandler.new)` | Must define `#call` |
| Zero-arity | `after_item_created -> { ... }` | Called without event argument |

## Multiple Handlers

Multiple handlers can be registered for the same event. They execute in registration order:

```ruby
config.events.after_item_created { |e| log(e) }           # runs first
config.events.after_item_created { |e| notify(e) }        # runs second
config.events.after_item_created { |e| index(e) }         # runs third
```

If handler 2 raises, handlers 1 and 3 still execute (error is caught after each).

## Callback Keys

The `CALLBACK_KEYS` constant defines valid event names:

```ruby
CALLBACK_KEYS = %i[after_item_created after_item_scraped after_fetch_completed].freeze
```

Registering an unknown event raises `ArgumentError`.

## Pipeline Integration Points

| Event | Triggered By | File |
|---|---|---|
| `after_item_created` | `EntryProcessor` after creating item | `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` |
| `after_item_scraped` | `ItemScraper` after scraping | `lib/source_monitor/scraping/item_scraper.rb` |
| `after_fetch_completed` | `EventPublisher` after fetch | `lib/source_monitor/fetching/completion/event_publisher.rb` |
| Item processors | `EntryProcessor` after item created | `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` |

## Best Practices

1. **Keep handlers lightweight** -- heavy work should be enqueued as background jobs
2. **Handlers should be idempotent** -- they may be retried or run multiple times
3. **Never raise in handlers** -- errors are caught but indicate problems
4. **Use item processors for normalization** -- they run close to creation
5. **Use event callbacks for side effects** -- notifications, indexing, analytics
