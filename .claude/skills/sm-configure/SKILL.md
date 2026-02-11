---
name: sm-configure
description: Use when configuring SourceMonitor engine settings via the DSL, including queue settings, HTTP client, fetching, health, scrapers, retention, scraping controls, events, model extensions, realtime, and authentication.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-configure: Engine Configuration DSL

Comprehensive reference for configuring SourceMonitor via `SourceMonitor.configure`.

## When to Use

- Adding or modifying settings in `config/initializers/source_monitor.rb`
- Understanding what configuration options are available
- Debugging configuration-related issues
- Setting up environment-specific overrides

## Configuration Entry Point

All configuration lives inside the `configure` block in the host app's initializer:

```ruby
SourceMonitor.configure do |config|
  # settings here
end
```

After the block executes, `ModelExtensions.reload!` runs automatically to apply any model changes. Restart web and worker processes after changes.

## Configuration Sections

The `config` object (`SourceMonitor::Configuration`) has 10 sub-sections plus top-level queue/job settings:

| Section | Accessor | Class |
|---|---|---|
| Top-level | `config.*` | `Configuration` |
| HTTP | `config.http` | `HTTPSettings` |
| Fetching | `config.fetching` | `FetchingSettings` |
| Health | `config.health` | `HealthSettings` |
| Scrapers | `config.scrapers` | `ScraperRegistry` |
| Retention | `config.retention` | `RetentionSettings` |
| Scraping | `config.scraping` | `ScrapingSettings` |
| Events | `config.events` | `Events` |
| Models | `config.models` | `Models` |
| Realtime | `config.realtime` | `RealtimeSettings` |
| Authentication | `config.authentication` | `AuthenticationSettings` |

See `reference/configuration-reference.md` for every setting with types, defaults, and examples.

## Quick Examples

### Queue Configuration
```ruby
config.queue_namespace = "source_monitor"
config.fetch_queue_name = "source_monitor_fetch"
config.fetch_queue_concurrency = 4
```

### HTTP Client
```ruby
config.http.timeout = 30
config.http.proxy = ENV["HTTP_PROXY"]
config.http.retry_max = 3
```

### Authentication (Devise)
```ruby
config.authentication.authenticate_with :authenticate_user!
config.authentication.authorize_with ->(c) { c.current_user&.admin? }
```

### Events
```ruby
config.events.after_item_created { |e| Notifier.new_item(e.item) }
config.events.register_item_processor ->(ctx) { Indexer.index(ctx.item) }
```

### Model Extensions
```ruby
config.models.table_name_prefix = "sm_"
config.models.source.include_concern "MyApp::SourceExtension"
config.models.item.validate :custom_check
```

### Realtime
```ruby
config.realtime.adapter = :redis
config.realtime.redis_url = ENV["REDIS_URL"]
```

## Helper APIs

```ruby
SourceMonitor.config                         # Current configuration
SourceMonitor.configure { |c| ... }          # Set configuration
SourceMonitor.reset_configuration!           # Revert to defaults (for tests)
SourceMonitor.events                         # Shortcut to config.events
SourceMonitor.queue_name(:fetch)             # Resolved queue name
SourceMonitor.queue_concurrency(:scrape)     # Resolved concurrency
SourceMonitor.mission_control_dashboard_path # Resolved MC path or nil
```

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/configuration.rb` | Main Configuration class |
| `lib/source_monitor/configuration/http_settings.rb` | HTTP client settings |
| `lib/source_monitor/configuration/fetching_settings.rb` | Adaptive scheduling |
| `lib/source_monitor/configuration/health_settings.rb` | Health monitoring |
| `lib/source_monitor/configuration/scraper_registry.rb` | Scraper adapter registry |
| `lib/source_monitor/configuration/retention_settings.rb` | Item retention |
| `lib/source_monitor/configuration/scraping_settings.rb` | Scraping controls |
| `lib/source_monitor/configuration/events.rb` | Event callbacks |
| `lib/source_monitor/configuration/models.rb` | Model extensions config |
| `lib/source_monitor/configuration/model_definition.rb` | Per-model definition |
| `lib/source_monitor/configuration/realtime_settings.rb` | Action Cable settings |
| `lib/source_monitor/configuration/authentication_settings.rb` | Auth settings |
| `lib/source_monitor/configuration/validation_definition.rb` | Validation wrapper |

## References

- `reference/configuration-reference.md` -- Complete settings reference
- `docs/configuration.md` -- Official configuration documentation
- `lib/generators/source_monitor/install/templates/source_monitor.rb.tt` -- Initializer template

## Testing

Reset configuration between tests:
```ruby
setup do
  SourceMonitor.reset_configuration!
end
```

Test custom configuration:
```ruby
test "custom queue name" do
  SourceMonitor.configure do |config|
    config.fetch_queue_name = "custom_fetch"
  end
  assert_equal "custom_fetch", SourceMonitor.queue_name(:fetch)
end
```

## Checklist

- [ ] Initializer exists at `config/initializers/source_monitor.rb`
- [ ] Queue names match `config/solid_queue.yml` entries
- [ ] Authentication hooks configured for host auth system
- [ ] HTTP timeouts appropriate for target feeds
- [ ] Retention policy set for production
- [ ] Workers restarted after configuration changes
