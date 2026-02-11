# Scraper Adapter Contract

Detailed specification of the interface required by custom scraper adapters.

Source: `lib/source_monitor/scrapers/base.rb`

## Inheritance Requirement

All scraper adapters **must** inherit from `SourceMonitor::Scrapers::Base`:

```ruby
class MyAdapter < SourceMonitor::Scrapers::Base
  def call
    # implementation
  end
end
```

The `ScraperRegistry` validates this at registration time and raises `ArgumentError` if the adapter does not inherit from `Base`.

## Constructor Signature

```ruby
def initialize(item:, source:, settings: nil, http: SourceMonitor::HTTP)
```

| Parameter | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The item to scrape |
| `source` | `SourceMonitor::Source` | The owning source/feed |
| `settings` | Hash/nil | Per-invocation setting overrides |
| `http` | Module | HTTP client module (default: `SourceMonitor::HTTP`) |

The constructor is defined on `Base` -- do not override it. Use `#call` for your logic.

## Required Instance Method: `#call`

Must return a `SourceMonitor::Scrapers::Base::Result`:

```ruby
Result = Struct.new(:status, :html, :content, :metadata, keyword_init: true)
```

### Result Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `status` | Symbol | Yes | `:success`, `:partial`, or `:failed` |
| `html` | String/nil | No | Raw HTML body from the fetch |
| `content` | String/nil | No | Extracted/cleaned text content |
| `metadata` | Hash/nil | No | Diagnostics and additional context |

### Status Values

| Status | Meaning |
|---|---|
| `:success` | Content fully extracted |
| `:partial` | Content extracted but incomplete (e.g., truncated, missing elements) |
| `:failed` | Unable to extract content |

### Metadata Conventions

On success:
```ruby
{
  url: "https://example.com/article",
  http_status: 200,
  content_type: "text/html",
  extraction_strategy: "custom",
  title: "Article Title"
}
```

On failure:
```ruby
{
  error: "fetch_error",       # Error classification
  message: "Connection refused", # Human-readable message
  url: "https://example.com/article",
  http_status: 500            # If available
}
```

## Optional Class Methods

### `self.adapter_name`

Default: derived from class name by removing `Scraper` suffix and underscoring.

```ruby
MyApp::Scrapers::Premium      # => "premium"
MyApp::Scrapers::CustomScraper # => "custom"
```

### `self.default_settings`

Default: `{}`

Return a Hash of adapter-specific default settings. These are merged with source-level and invocation-level overrides.

```ruby
def self.default_settings
  {
    api_key: nil,
    max_retries: 3,
    selectors: { content: "article", title: "h1" }
  }
end
```

### `self.call(item:, source:, settings: nil, http: SourceMonitor::HTTP)`

Default implementation creates a new instance and calls `#call`. Rarely needs to be overridden.

## Protected Accessors

Available inside `#call`:

| Accessor | Type | Description |
|---|---|---|
| `item` | `SourceMonitor::Item` | The item being scraped |
| `source` | `SourceMonitor::Source` | The owning source |
| `http` | Module | HTTP client module |
| `settings` | HashWithIndifferentAccess | Merged settings (see below) |

## Settings Merge Order

Settings are deep-merged in this priority order (later wins):

```
1. self.class.default_settings   (adapter defaults)
2. source.scrape_settings        (source-level, from DB JSON column)
3. settings parameter            (per-invocation overrides)
```

All keys are normalized to strings with `ActiveSupport::HashWithIndifferentAccess`, so you can access them with either string or symbol keys.

## Thread Safety

Adapters must be stateless and thread-safe:
- A new instance is created per invocation via `self.call`
- Use instance variables set in the constructor only
- Do not use class-level mutable state
- The `http` client is safe to share

## Error Handling

Adapters should:
1. Catch expected errors (network, parsing) and return a `Result` with `:failed` status
2. Let unexpected errors propagate (they will be caught by the scraping pipeline)
3. Never swallow errors silently -- populate `metadata` with error details

```ruby
def call
  # ... scraping logic ...
rescue Faraday::Error => error
  Result.new(
    status: :failed,
    metadata: { error: error.class.name, message: error.message }
  )
rescue StandardError => error
  Result.new(
    status: :failed,
    metadata: { error: error.class.name, message: error.message }
  )
end
```
