---
name: sm-event-handler
description: Use when working with SourceMonitor lifecycle events and callbacks, including after_item_created, after_item_scraped, after_fetch_completed, and item processors.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-event-handler: Lifecycle Events and Callbacks

Integrate with SourceMonitor's event system to respond to feed activity without monkey-patching.

## When to Use

- Wiring host app logic to engine lifecycle events
- Building notifications, indexing, or analytics on feed activity
- Understanding event payloads and when events fire
- Debugging event handler failures
- Implementing item processors for post-processing pipelines

## Event System Architecture

```
Feed Fetch Pipeline
  |
  +-> EntryProcessor creates item
  |     |
  |     +-> Events.after_item_created(event)      # ItemCreatedEvent
  |     +-> Events.run_item_processors(context)    # ItemProcessorContext
  |
  +-> ItemScraper scrapes content
  |     |
  |     +-> Events.after_item_scraped(event)       # ItemScrapedEvent
  |
  +-> Fetch completes
        |
        +-> Events.after_fetch_completed(event)    # FetchCompletedEvent
```

Events are dispatched synchronously. Errors in handlers are caught, logged, and do not halt the pipeline.

## Available Events

### `after_item_created`

Fires after a new item is created from a feed entry.

**Event struct:** `SourceMonitor::Events::ItemCreatedEvent`

| Field | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The newly created item |
| `source` | `SourceMonitor::Source` | The owning source/feed |
| `entry` | Object | The raw feed entry from Feedjira |
| `result` | Object | The creation result |
| `status` | String | Result status (e.g., `"created"`) |
| `occurred_at` | Time | When the event fired |

**Helper method:** `event.created?` -- returns true when `status == "created"`

```ruby
config.events.after_item_created do |event|
  NewItemNotifier.publish(event.item, source: event.source)
end
```

### `after_item_scraped`

Fires after an item has been scraped for content.

**Event struct:** `SourceMonitor::Events::ItemScrapedEvent`

| Field | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The scraped item |
| `source` | `SourceMonitor::Source` | The owning source |
| `result` | Object | The scrape result |
| `log` | `SourceMonitor::ScrapeLog` | The scrape log record |
| `status` | String | Result status |
| `occurred_at` | Time | When the event fired |

**Helper method:** `event.success?` -- returns true when `status != "failed"`

```ruby
config.events.after_item_scraped do |event|
  if event.success?
    SearchIndexer.reindex(event.item)
  else
    ErrorTracker.report("Scrape failed for item #{event.item.id}")
  end
end
```

### `after_fetch_completed`

Fires after a feed fetch finishes (success or failure).

**Event struct:** `SourceMonitor::Events::FetchCompletedEvent`

| Field | Type | Description |
|---|---|---|
| `source` | `SourceMonitor::Source` | The fetched source |
| `result` | Object | The fetch result |
| `status` | String | Result status |
| `occurred_at` | Time | When the event fired |

```ruby
config.events.after_fetch_completed do |event|
  Rails.logger.info "Fetch for #{event.source.name}: #{event.status}"
  MetricsCollector.record_fetch(event.source, event.status, event.occurred_at)
end
```

## Item Processors

Item processors are a separate pipeline that runs after each entry is processed. Unlike event callbacks, they receive an `ItemProcessorContext` and are designed for lightweight normalization or denormalized writes.

**Context struct:** `SourceMonitor::Events::ItemProcessorContext`

| Field | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The processed item |
| `source` | `SourceMonitor::Source` | The owning source |
| `entry` | Object | The raw feed entry |
| `result` | Object | The processing result |
| `status` | String | Result status |
| `occurred_at` | Time | When processing occurred |

```ruby
config.events.register_item_processor ->(context) {
  SearchIndexer.index(context.item)
}

config.events.register_item_processor ->(context) {
  context.item.update_column(:word_count, context.item.content&.split&.size || 0)
}
```

## Registering Handlers

### Block Form
```ruby
config.events.after_item_created do |event|
  # handle event
end
```

### Lambda/Proc Form
```ruby
handler = ->(event) { Analytics.track(event.item) }
config.events.after_item_created(handler)
```

### Callable Object Form
```ruby
class NewItemHandler
  def call(event)
    Notification.send(event.item, event.source)
  end
end

config.events.after_item_created(NewItemHandler.new)
```

All handlers must respond to `#call`. Zero-arity callables are supported (called without the event argument).

## Error Handling

Errors in event handlers are:
1. **Caught** -- they do not propagate or halt the pipeline
2. **Logged** -- via `Rails.logger.error` (or `warn` fallback)
3. **Formatted** as: `[SourceMonitor] <event_name> handler <handler.inspect> failed: <ErrorClass>: <message>`

This means handlers should be idempotent where possible, since a failure does not prevent subsequent handlers from running.

## Dispatching Internals

The `SourceMonitor::Events` module handles dispatch:

```ruby
# lib/source_monitor/events.rb
def dispatch(event_name, event)
  SourceMonitor.config.events.callbacks_for(event_name).each do |callback|
    invoke(callback, event)
  rescue StandardError => error
    log_handler_error(event_name, callback, error)
  end
end
```

Events are dispatched from:
- `Fetching::Completion::EventPublisher` -- fires `after_fetch_completed`
- `Fetching::FeedFetcher::EntryProcessor` -- fires `after_item_created` and runs item processors
- `Scraping::ItemScraper` -- fires `after_item_scraped`

## Common Use Cases

| Use Case | Event | Example |
|---|---|---|
| Send notifications on new items | `after_item_created` | Email, Slack, push |
| Index scraped content | `after_item_scraped` | Elasticsearch, Meilisearch |
| Track fetch statistics | `after_fetch_completed` | Custom metrics, dashboards |
| Normalize item data | `register_item_processor` | Word count, tag extraction |
| Sync to external systems | `after_item_created` | CRM, analytics, webhooks |

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/events.rb` | Event dispatch, structs, error handling |
| `lib/source_monitor/configuration/events.rb` | Callback registration DSL |
| `lib/source_monitor/fetching/completion/event_publisher.rb` | Fetch completion dispatch |
| `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` | Item creation dispatch |
| `lib/source_monitor/scraping/item_scraper.rb` | Scrape completion dispatch |

## References

- `reference/events-api.md` -- Full API reference with all event signatures
- `docs/configuration.md` -- Configuration documentation (Events section)

## Testing

```ruby
require "test_helper"

class EventHandlerTest < ActiveSupport::TestCase
  setup do
    SourceMonitor.reset_configuration!
    @source = create_source!
  end

  test "after_item_created fires with correct payload" do
    received = nil
    SourceMonitor.configure do |config|
      config.events.after_item_created { |event| received = event }
    end

    item = @source.items.create!(title: "Test", url: "https://example.com", external_id: "1")
    SourceMonitor::Events.after_item_created(item: item, source: @source, entry: nil, result: nil)

    assert_not_nil received
    assert_equal item, received.item
    assert_equal @source, received.source
  end

  test "handler errors are caught and logged" do
    SourceMonitor.configure do |config|
      config.events.after_fetch_completed { |_| raise "boom" }
    end

    # Should not raise
    assert_nothing_raised do
      SourceMonitor::Events.after_fetch_completed(source: @source, result: nil)
    end
  end
end
```

## Checklist

- [ ] Handler responds to `#call`
- [ ] Handler accepts the event struct or is zero-arity
- [ ] Handler is registered in `config/initializers/source_monitor.rb`
- [ ] Handler is idempotent (errors don't halt pipeline)
- [ ] Heavy work is enqueued as background jobs, not done inline
- [ ] Tests verify handler receives correct payload
- [ ] Tests verify error isolation (handler failures don't propagate)
