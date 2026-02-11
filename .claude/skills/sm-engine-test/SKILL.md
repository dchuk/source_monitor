---
name: sm-engine-test
description: Source Monitor engine test patterns and helpers. Use when writing or modifying tests for the Source Monitor engine, debugging test failures, setting up test isolation, or working with VCR/WebMock in this project.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Source Monitor Engine Tests

## Quick Start

```ruby
# Minimal test file
require "test_helper"

module SourceMonitor
  class MyFeatureTest < ActiveSupport::TestCase
    test "does something" do
      source = create_source!(name: "Test", feed_url: "https://example.com/feed.xml")
      assert source.persisted?
    end
  end
end
```

## Critical: Parallel Worker Caveat

**Single test files MUST use `PARALLEL_WORKERS=1`** due to a PG fork segfault bug (Ruby 3.4+ / pg 1.6+ / fork-based parallelism).

```bash
# Single file — REQUIRED
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb

# Full suite — works fine (handles PG connections properly)
bin/rails test

# Coverage mode — automatically uses threads, not forks
COVERAGE=1 PARALLEL_WORKERS=1 bin/rails test
```

## Test Helpers

All helpers are available in every test via `ActiveSupport::TestCase`.

| Helper | Purpose | Defined In |
|--------|---------|------------|
| `create_source!(attrs)` | Factory for Source records | `test/test_helper.rb` |
| `with_queue_adapter(adapter)` | Temporarily swap ActiveJob adapter | `test/test_helper.rb` |
| `with_inline_jobs { }` | Execute jobs inline in a block | `test/test_prof.rb` |
| `setup_once { }` | TestProf `before_all` for expensive setup | `test/test_prof.rb` |
| `clean_source_monitor_tables!` | Delete all engine records (FK-safe order) | `test/test_helper.rb` |
| `SourceMonitor.reset_configuration!` | Reset config to defaults (runs in setup) | automatic |

## Configuration Reset

Every test automatically calls `SourceMonitor.reset_configuration!` in setup. If you modify config in a test, it will be reset before the next test.

```ruby
test "custom config behavior" do
  SourceMonitor.configure do |config|
    config.fetching.min_interval_minutes = 10
  end

  # Test with custom config...
  assert_equal 10, SourceMonitor.config.fetching.min_interval_minutes
end
# Config is automatically reset after this test
```

For tests that explicitly need teardown:

```ruby
setup do
  SourceMonitor.reset_configuration!
end

teardown do
  SourceMonitor.reset_configuration!
end
```

## Factory Helper: create_source!

Creates a `SourceMonitor::Source` record, bypassing validations for speed.

```ruby
# Defaults
source = create_source!
# => name: "Test Source"
# => feed_url: "https://example.com/feed-<random>.xml"
# => website_url: "https://example.com"
# => fetch_interval_minutes: 60
# => scraper_adapter: "readability"

# Override any attribute
source = create_source!(
  name: "Custom Source",
  feed_url: "https://custom.example.com/feed.xml",
  active: false,
  adaptive_fetching_enabled: false,
  fetch_interval_minutes: 120
)
```

**Important:** `create_source!` uses `save!(validate: false)` so it skips model validations. This is intentional for test speed but means you can create records that would fail validation.

## WebMock Setup

WebMock is configured globally to block all external HTTP requests except localhost.

```ruby
# Stub a request
stub_request(:get, "https://example.com/feed.xml")
  .to_return(
    status: 200,
    body: File.read(file_fixture("feeds/rss_sample.xml")),
    headers: { "Content-Type" => "application/rss+xml" }
  )

# Stub with specific headers
stub_request(:get, url)
  .with(headers: { "If-None-Match" => '"etag123"' })
  .to_return(status: 304, headers: { "ETag" => '"etag123"' })

# Stub a timeout
stub_request(:get, url).to_raise(Faraday::TimeoutError.new("execution expired"))

# Stub a connection failure
stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))
```

## VCR Cassettes

VCR is configured to hook into WebMock. Cassettes are stored in `test/vcr_cassettes/`.

```ruby
test "fetches feed" do
  source = create_source!(feed_url: "https://www.ruby-lang.org/en/feeds/news.rss")

  VCR.use_cassette("source_monitor/fetching/rss_success") do
    result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
    assert_equal :fetched, result.status
  end
end
```

**Naming convention:** `source_monitor/<module>/<descriptor>` (e.g., `source_monitor/fetching/rss_success`).

## Test Isolation

### Scope Queries to Specific Records

Parallel tests share the database. Always scope assertions to records you created:

```ruby
# GOOD - scoped to specific source
assert_equal 3, SourceMonitor::Item.where(source: source).count

# BAD - counts all items across parallel tests
assert_equal 3, SourceMonitor::Item.count
```

### Use Unique Feed URLs

`create_source!` generates random feed URLs by default. When you need a specific URL, make it unique:

```ruby
source = create_source!(feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml")
```

### Clean Tables When Needed

For tests that need a blank-slate database:

```ruby
setup do
  clean_source_monitor_tables!
end
```

The cleanup order respects foreign keys: LogEntry > ScrapeLog > FetchLog > HealthCheckLog > ItemContent > Item > Source.

## Job Testing

```ruby
# Default adapter is :test (jobs are enqueued but not performed)
test "enqueues fetch job" do
  source = create_source!
  assert_enqueued_with(job: SourceMonitor::FetchSourceJob, args: [source]) do
    source.enqueue_fetch!
  end
end

# Execute jobs inline for integration tests
test "performs fetch end-to-end" do
  with_inline_jobs do
    # Jobs execute immediately when enqueued
  end
end

# Switch to a specific adapter temporarily
test "with async adapter" do
  with_queue_adapter(:async) do
    # ...
  end
end
```

## Test Types

| Type | Base Class | Location |
|------|-----------|----------|
| Model | `ActiveSupport::TestCase` | `test/models/source_monitor/` |
| Controller | `ActionDispatch::IntegrationTest` | `test/controllers/source_monitor/` |
| Library | `ActiveSupport::TestCase` | `test/lib/source_monitor/` |
| Generator | `Rails::Generators::TestCase` | `test/lib/generators/` |

## Common Patterns

### Testing with Notifications

```ruby
test "emits fetch finish event" do
  payloads = []
  ActiveSupport::Notifications.subscribed(
    ->(_name, _start, _finish, _id, payload) { payloads << payload },
    "source_monitor.fetch.finish"
  ) do
    FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
  end

  assert payloads.last[:success]
end
```

### Testing with Time Travel

```ruby
test "schedules next fetch" do
  travel_to Time.zone.parse("2024-01-01 10:00:00 UTC")

  # ... test logic ...

  assert_equal Time.current + 45.minutes, source.next_fetch_at
ensure
  travel_back
end
```

### Private Method Testing (via send)

```ruby
test "jitter_offset returns zero for zero interval" do
  fetcher = FeedFetcher.new(source: source)
  assert_equal 0, fetcher.send(:jitter_offset, 0)
end
```

## Running Tests

```bash
# Full suite
bin/rails test

# Single file (MUST use PARALLEL_WORKERS=1)
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb

# Verbose output
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb --verbose

# Single test by name
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb -n "test_is_valid_with_minimal_attributes"

# Coverage report
COVERAGE=1 PARALLEL_WORKERS=1 bin/rails test

# Random seed subset (via TestProf)
SAMPLE=10 bin/rails test
```

## File Fixtures

Test fixtures (feed XML files, etc.) are in `test/fixtures/`:

```ruby
body = File.read(file_fixture("feeds/rss_sample.xml"))
```

## Testing Checklist

- [ ] Test file requires `"test_helper"`
- [ ] Tests wrapped in `module SourceMonitor` namespace
- [ ] Queries scoped to specific test records (not global counts)
- [ ] Feed URLs are unique per test
- [ ] `PARALLEL_WORKERS=1` used when running single files
- [ ] WebMock stubs or VCR cassettes for any HTTP calls
- [ ] `SourceMonitor.reset_configuration!` used if config is modified
- [ ] `travel_back` called in `ensure` when using `travel_to`

## References

- [reference/test-helpers.md](reference/test-helpers.md) -- Detailed helper documentation
- [reference/test-patterns.md](reference/test-patterns.md) -- VCR, WebMock, and isolation patterns
