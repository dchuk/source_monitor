# Test Conventions

Guidelines for writing tests in the SourceMonitor engine.

## 1. Mocking Approach

**Primary:** Use Minitest `.stub` for all mocking needs.

```ruby
# GOOD: Stub a class method
SourceMonitor::Scrapers::Readability.stub(:call, result) do
  # test code
end

# GOOD: Stub an instance method on a specific object
connection_pool.stub(:with_connection, ->(&block) { block.call(fake) }) do
  # test code
end
```

**When `Class.new` is acceptable:** Only when you need a duck-type object implementing
multiple methods that `.stub` cannot express (e.g., a fake database connection with
`exec_query` returning different values based on SQL content).

```ruby
# ACCEPTABLE: Multiple methods with conditional logic
fake_connection = Class.new do
  # Document why .stub is insufficient
  def exec_query(sql)
    # conditional return based on SQL content
  end
end.new
```

**Avoid:** Mocha, rspec-mocks, or any external mocking library.

## 2. Test Naming

Convention: imperative mood (start with action verb).

Format: `"verb [condition] [expected outcome]"`

```ruby
# GOOD
test "creates item from RSS entry" do; end
test "raises error when feed URL is blank" do; end
test "returns empty array for inactive sources" do; end
test "enqueues fetch job after source creation" do; end

# BAD
test "test that it works" do; end
test "item creation" do; end
test "should create item" do; end  # avoid "should"
```

## 3. Job Testing

Default adapter is `:test` -- jobs are enqueued but not performed.

```ruby
# Unit tests: verify enqueueing only
test "enqueues fetch job" do
  source = create_source!
  assert_enqueued_with(job: SourceMonitor::FetchSourceJob, args: [source]) do
    source.enqueue_fetch!
  end
end

# Integration tests: execute jobs inline
test "performs fetch end-to-end" do
  with_inline_jobs do
    # jobs execute immediately when enqueued
  end
end
```

**Rule of thumb:** Unit tests use `:test` adapter. System and integration tests
use `with_inline_jobs` when job execution matters.

## 4. WebMock Stub Patterns

WebMock blocks all external HTTP except localhost. Every external request must be stubbed.

```ruby
# Use file_fixture for response bodies (not inline strings)
stub_request(:get, "https://example.com/feed.xml")
  .to_return(status: 200, body: File.read(file_fixture("feeds/rss_sample.xml")),
             headers: { "Content-Type" => "application/rss+xml" })

# For fetching tests, use shared helpers from FeedFetcherTestHelper:
#   stub_feed_request(url:, fixture:, status:, headers:)
#   stub_feed_timeout(url:)
#   stub_feed_not_found(url:)
```

For complex multi-request test scenarios, define reusable stub helpers in
test-specific helper files (see `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb`).

## 5. Time Travel

Prefer block form -- it auto-restores the clock:

```ruby
# GOOD: block form (auto travel_back)
travel_to Time.zone.parse("2025-10-01 12:00:00 UTC") do
  # time-dependent logic
end

# ACCEPTABLE: ensure-guarded (when block form won't work)
test "schedules next fetch" do
  travel_to Time.zone.parse("2025-10-01 12:00:00 UTC")
  # test logic
ensure
  travel_back
end
```

## 6. Test Isolation

**Scope queries to test-created records.** Parallel tests share the database.

```ruby
# GOOD
assert_equal 3, SourceMonitor::Item.where(source: source).count

# BAD -- counts records from other parallel tests
assert_equal 3, SourceMonitor::Item.count
```

**Use unique identifiers.** `create_source!` generates random feed URLs by default.
When specifying a URL, add randomness:

```ruby
source = create_source!(feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml")
```

**Configuration reset** is handled automatically in `setup` via
`SourceMonitor.reset_configuration!`. No manual reset needed unless you modify
config in teardown.

## 7. Factory Helpers

Use `create_source!` from `test_helper.rb` as the primary factory. For domain-specific
record creation, define helpers in the relevant test helper module (not inline in each test).

```ruby
# Available globally
source = create_source!(name: "My Source", active: false)

# Domain-specific helpers live in helper modules
# e.g., FeedFetcherTestHelper#build_source
```

## 8. Running Tests

```bash
# Full suite
bin/rails test

# Single file (MUST use PARALLEL_WORKERS=1)
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb

# Single test by name
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb \
  -n "test_is_valid_with_minimal_attributes"

# Coverage
COVERAGE=1 PARALLEL_WORKERS=1 bin/rails test
```

## References

- `test/test_helper.rb` -- setup, factory helpers, WebMock/VCR config
- `test/test_prof.rb` -- TestProf integration, `with_inline_jobs`, `setup_once`
- `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb` -- feed stub helpers
