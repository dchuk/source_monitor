# Test Helpers Reference

## create_source!(attributes = {})

**File:** `test/test_helper.rb:97-109`

Creates a `SourceMonitor::Source` record with sensible defaults, bypassing model validations.

### Default Values

| Attribute | Default |
|-----------|---------|
| `name` | `"Test Source"` |
| `feed_url` | `"https://example.com/feed-<random_hex>.xml"` |
| `website_url` | `"https://example.com"` |
| `fetch_interval_minutes` | `60` |
| `scraper_adapter` | `"readability"` |

### Usage

```ruby
# All defaults
source = create_source!

# Override specific attributes
source = create_source!(
  name: "My Feed",
  feed_url: "https://example.com/specific-feed.xml",
  active: false,
  adaptive_fetching_enabled: true,
  fetch_interval_minutes: 120,
  scraping_enabled: true,
  auto_scrape: true,
  custom_headers: { "X-Api-Key" => "secret123" },
  metadata: { "category" => "tech" }
)
```

### Implementation Detail

Uses `save!(validate: false)` intentionally. This means:
- Records skip URL normalization that happens during validation
- Records with duplicate feed_urls can be created
- Invalid data can be inserted (useful for edge case testing)

### Creating Related Records

```ruby
source = create_source!

# Items
item = source.items.create!(
  guid: "guid-1",
  title: "Item Title",
  url: "https://example.com/1",
  published_at: Time.current
)

# Fetch logs
source.fetch_logs.create!(
  success: true,
  started_at: Time.current,
  completed_at: Time.current,
  items_created: 1
)

# Scrape logs
source.scrape_logs.create!(
  item: item,
  success: true,
  started_at: Time.current,
  completed_at: Time.current,
  scraper_adapter: "readability"
)
```

---

## with_queue_adapter(adapter)

**File:** `test/test_helper.rb:111-117`

Temporarily swaps the ActiveJob queue adapter for the duration of a block.

### Usage

```ruby
test "enqueues with inline adapter" do
  with_queue_adapter(:inline) do
    # Jobs execute immediately
    source.enqueue_fetch!
  end
end

test "with test adapter" do
  with_queue_adapter(:test) do
    assert_enqueued_with(job: FetchSourceJob) do
      source.enqueue_fetch!
    end
  end
end
```

### Behavior

- Saves current adapter
- Sets new adapter
- Yields to block
- Restores previous adapter in `ensure` (always runs, even on exception)

---

## with_inline_jobs

**File:** `test/test_prof.rb:24-29`

Convenience wrapper around `with_queue_adapter(:inline)`.

### Usage

```ruby
test "performs complete fetch pipeline" do
  with_inline_jobs do
    # All enqueued jobs execute immediately
    SourceMonitor::FetchSourceJob.perform_later(source)
    source.reload
    assert source.last_fetched_at.present?
  end
end
```

---

## setup_once(setup_fixtures: false, &block)

**File:** `test/test_prof.rb:18-20`

Wraps TestProf's `before_all` for expensive setup that should run once per test class, not per test method.

### Usage

```ruby
class ExpensiveSetupTest < ActiveSupport::TestCase
  setup_once do
    @shared_source = create_source!(name: "Shared")
    3.times do |i|
      @shared_source.items.create!(
        guid: "item-#{i}",
        url: "https://example.com/#{i}"
      )
    end
  end

  test "source has items" do
    assert_equal 3, @shared_source.items.count
  end

  test "another test reuses same data" do
    assert @shared_source.persisted?
  end
end
```

### Caveats

- Data created in `setup_once` is rolled back after all tests in the class
- Use `setup_fixtures: true` if you need fixtures loaded in the `before_all` block
- Do NOT modify `setup_once` data in individual tests (it is shared across tests)

---

## clean_source_monitor_tables!

**File:** `test/test_helper.rb:85-93`

Deletes all records from engine tables in FK-safe order.

### Deletion Order

1. `SourceMonitor::LogEntry`
2. `SourceMonitor::ScrapeLog`
3. `SourceMonitor::FetchLog`
4. `SourceMonitor::HealthCheckLog`
5. `SourceMonitor::ItemContent`
6. `SourceMonitor::Item`
7. `SourceMonitor::Source`

### Usage

```ruby
setup do
  clean_source_monitor_tables!
end
```

### When to Use

- Tests that assert global counts (e.g., `Source.count`)
- Tests that need no pre-existing data
- Tests that are sensitive to data created by other tests in parallel

---

## SourceMonitor.reset_configuration!

**Automatically called** in setup for every `ActiveSupport::TestCase`.

Resets the `SourceMonitor::Configuration` instance to default values. This means:

- All queue names/concurrency reset to defaults
- HTTP settings (timeouts, user agent) reset
- Fetching adaptive interval settings reset
- Health thresholds reset
- Retention settings reset
- Realtime adapter reset to `:solid_cable`
- Authentication handlers cleared
- Events callbacks cleared
- Scraping settings reset
- Scraper registry cleared
- Model definitions reset

### Manual Usage

```ruby
setup do
  SourceMonitor.reset_configuration!
end

teardown do
  SourceMonitor.reset_configuration!
end
```

---

## Parallelization Configuration

**File:** `test/test_helper.rb:68-77`

```ruby
# With COVERAGE env var: single-threaded
parallelize(workers: 1, with: :threads)

# Without COVERAGE: uses system CPU count (fork-based)
parallelize(workers: :number_of_processors)

# Override with SOURCE_MONITOR_TEST_WORKERS env var
SOURCE_MONITOR_TEST_WORKERS=4 bin/rails test
```

### Environment Variables

| Variable | Effect |
|----------|--------|
| `COVERAGE` | Forces `workers: 1` with threads |
| `SOURCE_MONITOR_TEST_WORKERS` | Override worker count |
| `PARALLEL_WORKERS` | Rails built-in parallelism control |
| `SAMPLE` | TestProf: run random subset of tests |
| `SAMPLE_GROUPS` | TestProf: run random subset of test groups |
