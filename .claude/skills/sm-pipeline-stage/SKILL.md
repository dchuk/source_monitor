---
name: sm-pipeline-stage
description: How to add or modify fetch and scrape pipeline stages in SourceMonitor. Use when working on FeedFetcher, EntryProcessor, ItemCreator, completion handlers, or adding new processing steps to the feed ingestion pipeline.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# SourceMonitor Pipeline Stage Development

## Overview

The SourceMonitor fetch pipeline transforms RSS/Atom/JSON feeds into persisted `Item` records. The pipeline has two main phases: **fetching** (HTTP + parsing) and **item processing** (entry parsing + content extraction + persistence).

## Pipeline Architecture

```
FetchRunner (orchestrator)
  |
  +-- AdvisoryLock (PG advisory lock per source)
  |
  +-- FeedFetcher (HTTP fetch + parse + process)
  |     |
  |     +-- AdaptiveInterval (next_fetch_at calculation)
  |     +-- SourceUpdater (source record updates + fetch logs)
  |     +-- EntryProcessor (iterates feed entries)
  |           |
  |           +-- ItemCreator (per-entry)
  |                 |
  |                 +-- EntryParser (attribute extraction)
  |                 |     +-- MediaExtraction (enclosures, thumbnails)
  |                 |
  |                 +-- ContentExtractor (readability processing)
  |
  +-- Completion Handlers (post-fetch)
        +-- RetentionHandler (prune old items)
        +-- FollowUpHandler (enqueue scrape jobs)
        +-- EventPublisher (dispatch callbacks)
```

## Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `lib/source_monitor/fetching/fetch_runner.rb` | Orchestrator: lock, fetch, completion handlers | 142 |
| `lib/source_monitor/fetching/feed_fetcher.rb` | HTTP request, response routing, error handling | 285 |
| `lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb` | Dynamic fetch interval calculation | 141 |
| `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` | Persists source state + creates fetch logs | 200 |
| `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` | Iterates feed entries, calls ItemCreator | 89 |
| `lib/source_monitor/fetching/completion/retention_handler.rb` | Post-fetch item retention pruning | 30 |
| `lib/source_monitor/fetching/completion/follow_up_handler.rb` | Enqueues scrape jobs for new items | 37 |
| `lib/source_monitor/fetching/completion/event_publisher.rb` | Dispatches `after_fetch_completed` event | 22 |
| `lib/source_monitor/fetching/retry_policy.rb` | Per-error-type retry/circuit-breaker decisions | 85 |
| `lib/source_monitor/fetching/advisory_lock.rb` | PG advisory lock wrapper | 54 |
| `lib/source_monitor/items/item_creator.rb` | Find-or-create items by GUID/fingerprint | 174 |
| `lib/source_monitor/items/item_creator/entry_parser.rb` | Extracts all attributes from feed entries | 294 |
| `lib/source_monitor/items/item_creator/content_extractor.rb` | Readability-based content processing | 113 |
| `lib/source_monitor/items/item_creator/entry_parser/media_extraction.rb` | Enclosures, thumbnails, media content | 96 |

## Adding a New Pipeline Stage

### Option 1: Add a Completion Handler

Completion handlers run after every fetch, inside the `FetchRunner`. Best for cross-cutting post-fetch logic.

**Step 1:** Create the handler class:

```ruby
# lib/source_monitor/fetching/completion/my_handler.rb
# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module Completion
      class MyHandler
        def initialize(**deps)
          # Accept dependencies for testability
        end

        def call(source:, result:)
          return unless should_run?(source:, result:)
          # Your logic here
        end

        private

        def should_run?(source:, result:)
          result&.status == :fetched
        end
      end
    end
  end
end
```

**Step 2:** Wire it into `FetchRunner#initialize`:

```ruby
# In FetchRunner#initialize, add parameter:
def initialize(source:, ..., my_handler: nil)
  @my_handler = my_handler || Completion::MyHandler.new
end
```

**Step 3:** Call it in `FetchRunner#run` (inside the lock block):

```ruby
def run
  lock.with_lock do
    mark_fetching!
    result = fetcher_class.new(source: source).call
    retention_handler.call(source:, result:)
    follow_up_handler.call(source:, result:)
    my_handler.call(source:, result:)  # <-- Add here
    schedule_retry_if_needed(result)
    mark_complete!(result)
  end
  event_publisher.call(source:, result:)
  result
end
```

### Option 2: Add an Entry Processor Hook

Use `SourceMonitor::Events.run_item_processors` to add per-item processing without modifying the pipeline core.

```ruby
# In an initializer or engine setup:
SourceMonitor.configure do |config|
  config.events.on_item_processed do |source:, entry:, result:|
    # Custom per-item logic
  end
end
```

### Option 3: Add an EntryParser Extension

To extract new fields from feed entries, extend `EntryParser`:

```ruby
# Add a new extract method to EntryParser
def extract_my_field
  return unless entry.respond_to?(:my_field)
  string_or_nil(entry.my_field)
end
```

Then add it to the `parse` method's return hash.

### Option 4: Add a New Retention Strategy

```ruby
# lib/source_monitor/items/retention_strategies/archive.rb
module SourceMonitor
  module Items
    module RetentionStrategies
      class Archive
        def initialize(source:)
          @source = source
        end

        def apply(batch:, now: Time.current)
          # Your archival logic
          count = 0
          batch.each do |item|
            item.update!(archived_at: now)
            count += 1
          end
          count
        end

        private
        attr_reader :source
      end
    end
  end
end
```

Register in `RetentionPruner::STRATEGY_CLASSES`.

## Data Flow Details

See `reference/` for detailed documentation:
- `reference/feed-fetcher-architecture.md` -- FeedFetcher module structure
- `reference/completion-handlers.md` -- Completion handler patterns
- `reference/entry-processing.md` -- Entry processing pipeline

## Error Handling

The pipeline uses a typed error hierarchy rooted at `FetchError`:

| Error Class | Code | Trigger |
|-------------|------|---------|
| `TimeoutError` | `timeout` | Request timeout |
| `ConnectionError` | `connection` | Connection/SSL failure |
| `HTTPError` | `http_error` | Non-200/304 HTTP status |
| `ParsingError` | `parsing` | Feedjira parse failure |
| `UnexpectedResponseError` | `unexpected_response` | Any other StandardError |

Each error type maps to a `RetryPolicy` with configurable attempts, wait times, and circuit-breaker thresholds.

## Result Types

**FeedFetcher::Result** -- returned from `FeedFetcher#call`:
- `status` -- `:fetched`, `:not_modified`, or `:failed`
- `feed` -- parsed Feedjira feed object
- `response` -- HTTP response
- `body` -- raw response body
- `error` -- FetchError (on failure)
- `item_processing` -- EntryProcessingResult
- `retry_decision` -- RetryPolicy::Decision

**ItemCreator::Result** -- returned from `ItemCreator.call`:
- `item` -- the Item record
- `status` -- `:created` or `:updated`
- `matched_by` -- `:guid` or `:fingerprint` (for updates)

## Testing

- Test helpers: `create_source!`, `with_inline_jobs`
- WebMock blocks all external HTTP; stub responses manually
- Use `PARALLEL_WORKERS=1` for single test files
- Inject dependencies (client, lock_factory) for isolation

```ruby
test "processes new feed entries" do
  source = create_source!(feed_url: "https://example.com/feed.xml")
  stub_request(:get, source.feed_url).to_return(
    status: 200,
    body: File.read("test/fixtures/files/sample_feed.xml")
  )

  result = SourceMonitor::Fetching::FeedFetcher.new(source: source).call

  assert_equal :fetched, result.status
  assert result.item_processing.created.positive?
end
```

## Checklist

- [ ] New stage follows dependency injection pattern (accept collaborators in initialize)
- [ ] Stage has a `call(source:, result:)` interface (for completion handlers)
- [ ] Error handling returns gracefully (don't crash the pipeline)
- [ ] Instrumentation payload updated if stage adds metrics
- [ ] Tests cover success, failure, and skip conditions
- [ ] No N+1 queries (use `includes`/`preload`)
- [ ] Documented in this skill's reference files

## References

- `lib/source_monitor/fetching/` -- All fetching pipeline code
- `lib/source_monitor/items/` -- Item creation and retention
- `test/lib/source_monitor/fetching/` -- Fetching tests
- `test/lib/source_monitor/items/` -- Item processing tests
