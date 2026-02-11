# Test Patterns Reference

## VCR Cassette Patterns

### Configuration

```ruby
# test/test_helper.rb
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("vcr_cassettes", __dir__)
  config.hook_into :webmock
  config.ignore_localhost = true
end
```

### Recording a Cassette

```ruby
VCR.use_cassette("source_monitor/fetching/rss_success") do
  result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
end
```

### Cassette Naming Convention

```
test/vcr_cassettes/
  source_monitor/
    fetching/
      rss_success.yml
      atom_success.yml
      json_success.yml
    scraping/
      readability_success.yml
```

Pattern: `source_monitor/<module>/<format_or_scenario>`

### Multiple Formats

```ruby
feeds = {
  rss:  { url: "https://example.com/rss", parser: Feedjira::Parser::RSS },
  atom: { url: "https://example.com/atom", parser: Feedjira::Parser::Atom },
  json: { url: "https://example.com/json", parser: Feedjira::Parser::JSONFeed }
}

feeds.each do |format, data|
  source = create_source!(name: "#{format} feed", feed_url: data[:url])

  VCR.use_cassette("source_monitor/fetching/#{format}_success") do
    result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
    assert_equal :fetched, result.status
    assert_kind_of data[:parser], result.feed
  end
end
```

---

## WebMock Stub Patterns

### Basic Stubs

```ruby
# Successful response
stub_request(:get, url)
  .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

# 304 Not Modified
stub_request(:get, url)
  .to_return(status: 304, headers: { "ETag" => '"abc"' })

# 404 Not Found
stub_request(:get, url)
  .to_return(status: 404, body: "Not Found", headers: { "Content-Type" => "text/plain" })
```

### Conditional Headers

```ruby
# Match specific request headers
stub_request(:get, url)
  .with(headers: {
    "If-None-Match" => '"etag123"',
    "If-Modified-Since" => last_mod.httpdate
  })
  .to_return(status: 304, headers: { "ETag" => '"etag123"' })

# Custom headers on source
stub_request(:get, url)
  .with(headers: { "X-Api-Key" => "secret123" })
  .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })
```

### Error Stubs

```ruby
# Timeout
stub_request(:get, url).to_raise(Faraday::TimeoutError.new("execution expired"))

# Connection failure
stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

# SSL error
stub_request(:get, url).to_raise(Faraday::SSLError.new("SSL certificate problem"))

# Generic Faraday error
stub_request(:get, url).to_raise(Faraday::Error.new("something unexpected"))
```

### Sequential Responses

```ruby
# First call succeeds, second returns 304
stub_request(:get, url)
  .to_return(status: 200, body: body, headers: {
    "Content-Type" => "application/rss+xml",
    "ETag" => '"abcd1234"'
  })

# Re-stub for second call with conditional headers
stub_request(:get, url)
  .with(headers: { "If-None-Match" => '"abcd1234"' })
  .to_return(status: 304, headers: { "ETag" => '"abcd1234"' })
```

### Using File Fixtures

```ruby
body = File.read(file_fixture("feeds/rss_sample.xml"))

stub_request(:get, url)
  .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })
```

---

## Test Isolation Patterns

### Problem: Parallel Test Contamination

Tests run in parallel with fork-based workers. Each worker shares the database. If Test A creates a Source and Test B counts all Sources, Test B may see Test A's data.

### Solution: Scope All Queries

```ruby
# CORRECT: scope to specific records
assert_equal 3, SourceMonitor::Item.where(source: source).count
assert_includes Source.active, my_source
assert_not_includes Source.active, inactive_source

# INCORRECT: global counts
assert_equal 3, SourceMonitor::Item.count
assert_equal 1, Source.active.count
```

### Solution: Unique Feed URLs

`create_source!` auto-generates unique URLs:

```ruby
# Default: unique hex suffix
source = create_source!  # feed_url: "https://example.com/feed-a1b2c3d4.xml"

# When specifying URL, ensure uniqueness
source = create_source!(feed_url: "https://example.com/my-test-#{SecureRandom.hex(4)}.xml")
```

### Solution: Clean Tables

For tests that must assert global state:

```ruby
class GlobalStateTest < ActiveSupport::TestCase
  setup do
    clean_source_monitor_tables!
  end

  test "no sources exist initially" do
    assert_equal 0, SourceMonitor::Source.count
  end
end
```

---

## Controller Test Patterns

### Basic CRUD

```ruby
module SourceMonitor
  class SourcesControllerTest < ActionDispatch::IntegrationTest
    test "index returns success" do
      get "/source_monitor/sources"
      assert_response :success
    end

    test "create saves source" do
      assert_difference -> { Source.count }, 1 do
        post "/source_monitor/sources", params: {
          source: {
            name: "New Source",
            feed_url: "https://example.com/feed.xml",
            fetch_interval_minutes: 60
          }
        }
      end
    end
  end
end
```

### Turbo Stream Responses

```ruby
test "destroy responds with turbo stream" do
  source = create_source!

  delete source_monitor.source_path(source), as: :turbo_stream

  assert_response :success
  assert_equal "text/vnd.turbo-stream.html", response.media_type
  assert_includes response.body, %(<turbo-stream action="remove")
end
```

### Input Sanitization

```ruby
test "sanitizes XSS in params" do
  post "/source_monitor/sources", params: {
    source: {
      name: "<script>alert(1)</script>Example",
      feed_url: "https://example.com/feed.xml"
    }
  }

  source = Source.order(:created_at).last
  refute_includes source.name, "<"
end
```

---

## Model Test Patterns

### Validation Testing

```ruby
test "rejects invalid feed URLs" do
  source = Source.new(name: "Bad", feed_url: "ftp://example.com/feed.xml")
  assert_not source.valid?
  assert_includes source.errors[:feed_url], "must be a valid HTTP(S) URL"
end

test "enforces unique feed URLs" do
  Source.create!(name: "First", feed_url: "https://example.com/feed")
  duplicate = Source.new(name: "Second", feed_url: "https://example.com/feed")
  assert_not duplicate.valid?
  assert_includes duplicate.errors[:feed_url], "has already been taken"
end
```

### Scope Testing

```ruby
test "scopes reflect expected states" do
  healthy = Source.create!(name: "Healthy", feed_url: unique_url, next_fetch_at: 1.minute.ago)
  inactive = Source.create!(name: "Inactive", feed_url: unique_url, active: false)

  assert_includes Source.active, healthy
  assert_not_includes Source.active, inactive
end
```

### Database Constraint Testing

```ruby
test "database rejects invalid fetch_status values" do
  source = create_source!

  error = assert_raises(ActiveRecord::StatementInvalid) do
    source.update_columns(fetch_status: "bogus")
  end

  assert_match(/check_fetch_status_values/i, error.message)
end
```

---

## Library Test Patterns

### Private Method Helpers

Some test files define private helpers to build test objects:

```ruby
class FeedFetcherTest < ActiveSupport::TestCase
  private

  def build_source(name:, feed_url:, fetch_interval_minutes: 360, adaptive_fetching_enabled: true)
    create_source!(
      name: name,
      feed_url: feed_url,
      fetch_interval_minutes: fetch_interval_minutes,
      adaptive_fetching_enabled: adaptive_fetching_enabled
    )
  end
end
```

### Singleton Method Stubbing

For stubbing class methods without external mocking libraries:

```ruby
singleton = SourceMonitor::Items::ItemCreator.singleton_class
singleton.alias_method :call_without_stub, :call
singleton.define_method(:call) do |source:, entry:|
  raise StandardError, "forced failure"
end

begin
  # ... test logic ...
ensure
  singleton.alias_method :call, :call_without_stub
  singleton.remove_method :call_without_stub
end
```

### Minitest Mock/Stub

```ruby
test "handles policy error" do
  SourceMonitor::Fetching::RetryPolicy.stub(:new, ->(**_) { raise StandardError, "policy exploded" }) do
    result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
    assert_equal :failed, result.status
  end
end
```

---

## Time Travel Pattern

Always use `ensure` to call `travel_back`:

```ruby
test "schedules future fetch" do
  travel_to Time.zone.parse("2024-01-01 10:00:00 UTC")

  source = create_source!(fetch_interval_minutes: 60)
  # ... perform fetch ...

  source.reload
  assert_equal Time.current + 45.minutes, source.next_fetch_at
ensure
  travel_back
end
```

---

## ActiveSupport::Notifications Testing

```ruby
test "emits instrumentation event" do
  finish_payloads = []

  ActiveSupport::Notifications.subscribed(
    ->(_name, _start, _finish, _id, payload) { finish_payloads << payload },
    "source_monitor.fetch.finish"
  ) do
    FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
  end

  payload = finish_payloads.last
  assert payload[:success]
  assert_equal :fetched, payload[:status]
  assert_equal 200, payload[:http_status]
  assert_equal source.id, payload[:source_id]
end
```

---

## Difference Assertions

```ruby
# Single counter
assert_difference -> { Source.count }, 1 do
  post "/source_monitor/sources", params: { ... }
end

# Multiple counters
assert_difference [
  -> { SourceMonitor::Source.count },
  -> { SourceMonitor::Item.count },
  -> { SourceMonitor::FetchLog.count }
], -1 do
  delete source_monitor.source_path(source), as: :turbo_stream
end

# No change
assert_no_difference "Source.count" do
  post "/source_monitor/sources", params: { source: { name: "" } }
end
```
