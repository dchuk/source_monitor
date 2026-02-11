---
name: sm-scraper-adapter
description: Use when creating custom scraper adapters for SourceMonitor, inheriting from Scrapers::Base, implementing the adapter contract, or registering/unregistering scrapers.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-scraper-adapter: Custom Scraper Adapters

Build custom content scrapers that integrate with SourceMonitor's scraping pipeline.

## When to Use

- Creating a new scraper adapter for a specific content type or source
- Customizing how content is fetched and parsed
- Understanding the scraper adapter contract
- Registering or swapping scraper adapters in configuration
- Debugging scraper failures

## Architecture Overview

```
SourceMonitor::Scrapers::Base (abstract)
  |
  +-- SourceMonitor::Scrapers::Readability (built-in)
  +-- MyApp::Scrapers::Custom (your adapter)
```

Scrapers are registered in configuration and selected per-source. Each adapter:
1. Receives an `item`, `source`, and merged `settings` hash
2. Performs HTTP fetching and content parsing
3. Returns a `Result` struct with status, HTML, content, and metadata

## The Adapter Contract

### Base Class: `SourceMonitor::Scrapers::Base`

Location: `lib/source_monitor/scrapers/base.rb`

All custom scrapers **must** inherit from `SourceMonitor::Scrapers::Base`.

### Required: `#call` Instance Method

Must return a `SourceMonitor::Scrapers::Base::Result`:

```ruby
Result = Struct.new(:status, :html, :content, :metadata, keyword_init: true)
```

| Field | Type | Description |
|---|---|---|
| `status` | Symbol | `:success`, `:partial`, or `:failed` |
| `html` | String/nil | Raw HTML fetched from the URL |
| `content` | String/nil | Extracted/cleaned text content |
| `metadata` | Hash/nil | Diagnostics: headers, timings, URL, error info |

### Class Methods (Optional Overrides)

| Method | Default | Description |
|---|---|---|
| `self.adapter_name` | Derived from class name | Name used in registry |
| `self.default_settings` | `{}` | Default settings hash for this adapter |
| `self.call(item:, source:, settings:, http:)` | Creates instance, calls `#call` | Class-level entry point |

### Protected Accessors

Available inside `#call`:

| Accessor | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The item being scraped |
| `source` | `SourceMonitor::Source` | The owning source |
| `http` | Module | HTTP client module (`SourceMonitor::HTTP`) |
| `settings` | HashWithIndifferentAccess | Merged settings (see Settings Merging) |

### Settings Merging

Settings are merged in priority order:
1. `self.class.default_settings` (adapter defaults)
2. `source.scrape_settings` (source-level overrides)
3. `settings` parameter (per-invocation overrides)

All keys are normalized to strings with indifferent access.

## Creating a Custom Adapter

### Step 1: Create the Adapter Class

```ruby
# app/scrapers/my_app/scrapers/premium.rb
module MyApp
  module Scrapers
    class Premium < SourceMonitor::Scrapers::Base
      def self.default_settings
        {
          api_key: nil,
          extract_images: true,
          timeout: 30
        }
      end

      def call
        url = item.canonical_url.presence || item.url
        return failure("missing_url", "No URL available") unless url.present?

        response = fetch_content(url)
        return failure("fetch_failed", response[:error]) unless response[:success]

        content = extract_content(response[:body])

        Result.new(
          status: :success,
          html: response[:body],
          content: content,
          metadata: {
            url: url,
            http_status: response[:status],
            extraction_method: "premium"
          }
        )
      rescue StandardError => error
        failure(error.class.name, error.message)
      end

      private

      def fetch_content(url)
        conn = http.client(
          timeout: settings[:timeout],
          headers: { "Authorization" => "Bearer #{settings[:api_key]}" }
        )
        response = conn.get(url)
        { success: true, body: response.body, status: response.status }
      rescue Faraday::Error => e
        { success: false, error: e.message }
      end

      def extract_content(html)
        # Your custom extraction logic
        html.gsub(/<[^>]+>/, " ").squeeze(" ").strip
      end

      def failure(error, message)
        Result.new(
          status: :failed,
          html: nil,
          content: nil,
          metadata: { error: error, message: message }
        )
      end
    end
  end
end
```

### Step 2: Register the Adapter

```ruby
# config/initializers/source_monitor.rb
SourceMonitor.configure do |config|
  config.scrapers.register(:premium, "MyApp::Scrapers::Premium")
end
```

### Step 3: Assign to Sources

Set the scraper adapter name on individual sources. The source's `scrape_settings` JSON column can hold adapter-specific overrides.

## Built-in Adapter: Readability

Location: `lib/source_monitor/scrapers/readability.rb`

The built-in Readability adapter:
1. Fetches HTML via `HttpFetcher`
2. Parses content via `ReadabilityParser`
3. Supports CSS selector overrides via settings

Default settings structure:
```ruby
{
  http: { headers: {...}, timeout: 15, open_timeout: 5, proxy: nil },
  selectors: { content: nil, title: nil },
  readability: {
    remove_unlikely_candidates: true,
    clean_conditionally: true,
    retry_length: 250,
    min_text_length: 25
  }
}
```

## Registration API

```ruby
# Register by class
config.scrapers.register(:custom, MyApp::Scrapers::Custom)

# Register by string (lazy constantization)
config.scrapers.register(:custom, "MyApp::Scrapers::Custom")

# Unregister
config.scrapers.unregister(:custom)

# Look up
adapter_class = config.scrapers.adapter_for(:custom)

# Iterate
config.scrapers.each { |name, klass| puts "#{name}: #{klass}" }
```

Name validation: must match `/\A[a-z0-9_]+\z/i`, normalized to lowercase.

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/scrapers/base.rb` | Abstract base class and Result struct |
| `lib/source_monitor/scrapers/readability.rb` | Built-in Readability adapter |
| `lib/source_monitor/scrapers/fetchers/http_fetcher.rb` | HTTP fetching helper |
| `lib/source_monitor/scrapers/parsers/readability_parser.rb` | Content parsing |
| `lib/source_monitor/configuration/scraper_registry.rb` | Registration/lookup |
| `lib/source_monitor/scraping/item_scraper.rb` | Scraping orchestration |

## References

- `reference/adapter-contract.md` -- Detailed interface specification
- `reference/example-adapter.md` -- Complete working example
- `lib/source_monitor/scrapers/readability.rb` -- Reference implementation

## Testing

```ruby
require "test_helper"

class PremiumScraperTest < ActiveSupport::TestCase
  setup do
    @source = create_source!
    @item = @source.items.create!(
      title: "Test",
      url: "https://example.com/article",
      external_id: "test-1"
    )
  end

  test "scrapes content successfully" do
    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: "<html><body><p>Content</p></body></html>")

    result = MyApp::Scrapers::Premium.call(item: @item, source: @source)

    assert_equal :success, result.status
    assert_includes result.content, "Content"
    assert_equal 200, result.metadata[:http_status]
  end

  test "handles fetch failure" do
    stub_request(:get, "https://example.com/article")
      .to_return(status: 500, body: "Error")

    result = MyApp::Scrapers::Premium.call(item: @item, source: @source)

    assert_equal :failed, result.status
  end

  test "handles missing URL" do
    @item.update!(url: nil)
    result = MyApp::Scrapers::Premium.call(item: @item, source: @source)

    assert_equal :failed, result.status
    assert_equal "missing_url", result.metadata[:error]
  end
end
```

## Checklist

- [ ] Adapter inherits from `SourceMonitor::Scrapers::Base`
- [ ] `#call` returns a `Result` struct
- [ ] `status` is one of `:success`, `:partial`, `:failed`
- [ ] `metadata` includes `url` and error details on failure
- [ ] `self.default_settings` defined if adapter has configurable options
- [ ] Adapter registered in initializer
- [ ] Exception handling catches `StandardError` in `#call`
- [ ] Uses `http` accessor for HTTP requests (thread-safe)
- [ ] Tests cover success, failure, and edge cases
