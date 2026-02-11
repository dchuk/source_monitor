---
name: sm-configuration-setting
description: How to add or modify configuration settings in the Source Monitor engine. Use when adding a new config option, modifying defaults, creating a new settings section, or understanding the configuration architecture.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Source Monitor Configuration Settings

## Architecture Overview

The `SourceMonitor::Configuration` class was refactored from 655 lines into a lean 87-line orchestrator plus 12 extracted settings files. Each settings file follows a consistent pattern.

```
lib/source_monitor/configuration.rb          # Main class (87 lines)
lib/source_monitor/configuration/
  authentication_settings.rb                  # Auth handlers
  events.rb                                   # Callbacks and processors
  fetching_settings.rb                        # Adaptive interval tuning
  health_settings.rb                          # Health monitoring thresholds
  http_settings.rb                            # HTTP client defaults
  model_definition.rb                         # Concern/validation injection
  models.rb                                   # Model definitions registry
  realtime_settings.rb                        # ActionCable adapter config
  retention_settings.rb                       # Item retention policies
  scraper_registry.rb                         # Scraper adapter registry
  scraping_settings.rb                        # Scraping concurrency limits
  validation_definition.rb                    # Validation DSL
```

## How Configuration Works

```ruby
# In host app initializer
SourceMonitor.configure do |config|
  config.fetching.min_interval_minutes = 10
  config.http.timeout = 30
  config.retention.strategy = :soft_delete
end

# Access at runtime
SourceMonitor.config.fetching.min_interval_minutes  # => 10
```

The `config` object is a `SourceMonitor::Configuration` instance. Sub-sections are accessed via reader methods that return settings objects.

## Adding a Setting to an Existing Section

### Step 1: Identify the Settings File

| Setting Category | File | Class |
|-----------------|------|-------|
| HTTP client | `http_settings.rb` | `HTTPSettings` |
| Adaptive fetching | `fetching_settings.rb` | `FetchingSettings` |
| Health monitoring | `health_settings.rb` | `HealthSettings` |
| Scraping limits | `scraping_settings.rb` | `ScrapingSettings` |
| Item retention | `retention_settings.rb` | `RetentionSettings` |
| Realtime/cable | `realtime_settings.rb` | `RealtimeSettings` |
| Authentication | `authentication_settings.rb` | `AuthenticationSettings` |
| Events/callbacks | `events.rb` | `Events` |
| Scraper adapters | `scraper_registry.rb` | `ScraperRegistry` |
| Model extensions | `models.rb` / `model_definition.rb` | `Models` / `ModelDefinition` |

### Step 2: Add the Attribute

```ruby
# lib/source_monitor/configuration/fetching_settings.rb
class FetchingSettings
  attr_accessor :min_interval_minutes,
    :max_interval_minutes,
    :increase_factor,
    :decrease_factor,
    :failure_increase_factor,
    :jitter_percent,
    :my_new_setting              # <-- Add here

  def reset!
    @min_interval_minutes = 5
    @max_interval_minutes = 24 * 60
    @increase_factor = 1.25
    @decrease_factor = 0.75
    @failure_increase_factor = 1.5
    @jitter_percent = 0.1
    @my_new_setting = "default"  # <-- Set default here
  end
end
```

### Step 3: Write Tests

```ruby
# test/lib/source_monitor/configuration_test.rb
test "my_new_setting has correct default" do
  assert_equal "default", SourceMonitor.config.fetching.my_new_setting
end

test "my_new_setting can be overridden" do
  SourceMonitor.configure do |config|
    config.fetching.my_new_setting = "custom"
  end
  assert_equal "custom", SourceMonitor.config.fetching.my_new_setting
end
```

### Step 4: Verify Reset

Ensure `reset!` restores the default. The test suite calls `SourceMonitor.reset_configuration!` in setup, which recreates the entire Configuration object.

## Adding a Setting with Validation

For settings that need input normalization or validation, use custom setters:

```ruby
class ScrapingSettings
  attr_accessor :max_in_flight_per_source, :max_bulk_batch_size

  # Custom setter with normalization
  def max_in_flight_per_source=(value)
    @max_in_flight_per_source = normalize_numeric(value)
  end

  private

  def normalize_numeric(value)
    return nil if value.nil?
    return nil if value == ""
    integer = value.respond_to?(:to_i) ? value.to_i : value
    integer.positive? ? integer : nil
  end
end
```

For enum-style settings with strict validation:

```ruby
class RetentionSettings
  def strategy=(value)
    normalized = normalize_strategy(value)
    @strategy = normalized unless normalized.nil?
  end

  private

  def normalize_strategy(value)
    return :destroy if value.nil?
    if value.respond_to?(:to_sym)
      candidate = value.to_sym
      raise ArgumentError, "Invalid retention strategy #{value.inspect}" unless %i[destroy soft_delete].include?(candidate)
      candidate
    else
      raise ArgumentError, "Invalid retention strategy #{value.inspect}"
    end
  end
end
```

## Creating a New Settings Section

### Step 1: Create the Settings Class

```ruby
# lib/source_monitor/configuration/notifications_settings.rb
# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class NotificationsSettings
      attr_accessor :enabled, :channels, :throttle_seconds

      def initialize
        reset!
      end

      def reset!
        @enabled = true
        @channels = []
        @throttle_seconds = 60
      end
    end
  end
end
```

### Step 2: Register in Configuration

```ruby
# lib/source_monitor/configuration.rb
require "source_monitor/configuration/notifications_settings"

class Configuration
  attr_reader :http, :scrapers, :retention, :events, :models,
    :realtime, :fetching, :health, :authentication, :scraping,
    :notifications  # <-- Add reader

  def initialize
    # ... existing initialization ...
    @notifications = NotificationsSettings.new  # <-- Initialize
  end
end
```

### Step 3: Write Tests

```ruby
test "notifications settings have correct defaults" do
  settings = SourceMonitor.config.notifications
  assert_equal true, settings.enabled
  assert_equal [], settings.channels
  assert_equal 60, settings.throttle_seconds
end

test "notifications settings can be configured" do
  SourceMonitor.configure do |config|
    config.notifications.enabled = false
    config.notifications.channels = [:email, :slack]
    config.notifications.throttle_seconds = 30
  end

  settings = SourceMonitor.config.notifications
  assert_equal false, settings.enabled
  assert_equal [:email, :slack], settings.channels
  assert_equal 30, settings.throttle_seconds
end
```

## Patterns by Section Type

### Simple Accessor Pattern (FetchingSettings, HealthSettings)

Plain `attr_accessor` with defaults in `reset!`. No validation.

### Normalized Setter Pattern (ScrapingSettings)

Custom setter that normalizes input (strings to integers, negatives to nil).

### Enum Setter Pattern (RetentionSettings, RealtimeSettings)

Custom setter that validates against an allowed list and raises `ArgumentError`.

### Handler/Callback Pattern (AuthenticationSettings, Events)

Registration methods that accept symbols, lambdas, or blocks.

### Registry Pattern (ScraperRegistry)

Named registration with lookup, unregistration, and enumeration.

### Nested Object Pattern (RealtimeSettings::SolidCableOptions)

Sub-objects with their own `reset!` and `to_h` methods.

## Testing Checklist

- [ ] Default value is correct
- [ ] Value can be overridden via `SourceMonitor.configure`
- [ ] `reset!` restores the default (tested via `SourceMonitor.reset_configuration!`)
- [ ] Validation raises `ArgumentError` for invalid values (if applicable)
- [ ] String/nil normalization works correctly (if applicable)
- [ ] Test file: `test/lib/source_monitor/configuration_test.rb`
- [ ] Run: `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb`

## References

- [reference/settings-catalog.md](reference/settings-catalog.md) -- All settings sections with their attributes
- [reference/settings-pattern.md](reference/settings-pattern.md) -- Step-by-step pattern for adding settings
