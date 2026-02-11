# Completion Handlers

## Overview

Completion handlers are post-fetch processing steps managed by `FetchRunner`. They execute inside the advisory lock (except `EventPublisher`, which runs after the lock is released).

## Execution Order

```
lock.with_lock do
  mark_fetching!
  result = fetcher.call
  1. RetentionHandler   -- prune old items
  2. FollowUpHandler    -- enqueue scrape jobs for new items
  3. schedule_retry     -- re-enqueue on transient failure
  mark_complete!
end
4. EventPublisher       -- dispatch after_fetch_completed callback (outside lock)
```

## RetentionHandler

**File:** `lib/source_monitor/fetching/completion/retention_handler.rb`

Applies item retention pruning after every fetch.

```ruby
class RetentionHandler
  def initialize(pruner: SourceMonitor::Items::RetentionPruner)
  def call(source:, result:)
    pruner.call(source:, strategy: SourceMonitor.config.retention.strategy)
  end
end
```

- Delegates to `RetentionPruner` which supports age-based and count-based limits
- Rescues errors gracefully (logs and returns nil)
- Strategy comes from global config (`:destroy` or `:soft_delete`)

### RetentionPruner Details

Two pruning modes:
1. **Age-based** (`items_retention_days`): Removes items older than N days (uses `COALESCE(published_at, created_at)`)
2. **Count-based** (`max_items`): Keeps only the N most recent items

Strategies:
- `Destroy` -- calls `item.destroy!` per record
- `SoftDelete` -- sets `deleted_at` timestamp, adjusts `items_count` counter

Configuration priority: source-level setting > global config.

## FollowUpHandler

**File:** `lib/source_monitor/fetching/completion/follow_up_handler.rb`

Enqueues scrape jobs for newly created items when auto-scraping is enabled.

```ruby
class FollowUpHandler
  def initialize(enqueuer_class:, job_class:)
  def call(source:, result:)
    return unless should_enqueue?(source:, result:)
    result.item_processing.created_items.each do |item|
      next unless item.present? && item.scraped_at.nil?
      enqueuer_class.enqueue(item:, source:, job_class:, reason: :auto)
    end
  end
end
```

Guard conditions:
- Result status must be `:fetched`
- Source must have `scraping_enabled?` and `auto_scrape?`
- At least one item was created
- Item must not already be scraped (`scraped_at.nil?`)

## EventPublisher

**File:** `lib/source_monitor/fetching/completion/event_publisher.rb`

Dispatches the `after_fetch_completed` callback to all registered listeners.

```ruby
class EventPublisher
  def initialize(dispatcher: SourceMonitor::Events)
  def call(source:, result:)
    dispatcher.after_fetch_completed(source:, result:)
  end
end
```

- Runs **outside** the advisory lock to prevent long-running callbacks from holding the lock
- The health monitoring system (`SourceMonitor::Health`) registers a callback here
- Callbacks are registered via `SourceMonitor.config.events.after_fetch_completed(lambda)`

## Adding a New Completion Handler

### Pattern

```ruby
# lib/source_monitor/fetching/completion/my_handler.rb
module SourceMonitor
  module Fetching
    module Completion
      class MyHandler
        def initialize(**deps)
          @dependency = deps[:dependency] || DefaultDependency
        end

        def call(source:, result:)
          return unless should_run?(source:, result:)
          # Your logic
        rescue StandardError => error
          Rails.logger.error("[SourceMonitor] MyHandler failed: #{error.message}")
          nil
        end

        private

        attr_reader :dependency

        def should_run?(source:, result:)
          result&.status == :fetched
        end
      end
    end
  end
end
```

### Wiring

1. Add require in `fetch_runner.rb`
2. Add parameter to `FetchRunner#initialize` with default instance
3. Add `attr_reader` for the handler
4. Call `my_handler.call(source:, result:)` in `#run`
5. Decide placement: inside lock (for data consistency) or outside (for non-critical work)

### Testing

```ruby
test "my_handler is called on successful fetch" do
  handler = Minitest::Mock.new
  handler.expect(:call, nil, source: source, result: anything)

  runner = FetchRunner.new(source: source, my_handler: handler)
  stub_successful_fetch(source)
  runner.run

  handler.verify
end
```
