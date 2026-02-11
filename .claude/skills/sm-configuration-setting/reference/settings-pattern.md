# Step-by-Step: Adding a Configuration Setting

## Scenario A: Add to Existing Section

### Example: Add `stale_threshold_hours` to FetchingSettings

**Step 1: Edit the settings file**

```ruby
# lib/source_monitor/configuration/fetching_settings.rb
class FetchingSettings
  attr_accessor :min_interval_minutes,
    :max_interval_minutes,
    :increase_factor,
    :decrease_factor,
    :failure_increase_factor,
    :jitter_percent,
    :stale_threshold_hours        # ADD: new accessor

  def reset!
    @min_interval_minutes = 5
    @max_interval_minutes = 24 * 60
    @increase_factor = 1.25
    @decrease_factor = 0.75
    @failure_increase_factor = 1.5
    @jitter_percent = 0.1
    @stale_threshold_hours = 48   # ADD: default value
  end
end
```

**Step 2: Write tests**

```ruby
# test/lib/source_monitor/configuration_test.rb

test "stale_threshold_hours has correct default" do
  assert_equal 48, SourceMonitor.config.fetching.stale_threshold_hours
end

test "stale_threshold_hours can be overridden" do
  SourceMonitor.configure do |config|
    config.fetching.stale_threshold_hours = 72
  end
  assert_equal 72, SourceMonitor.config.fetching.stale_threshold_hours
end

test "stale_threshold_hours resets with configuration" do
  SourceMonitor.configure do |config|
    config.fetching.stale_threshold_hours = 72
  end
  SourceMonitor.reset_configuration!
  assert_equal 48, SourceMonitor.config.fetching.stale_threshold_hours
end
```

**Step 3: Run tests**

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb
```

---

## Scenario B: Add Setting with Validation

### Example: Add validated `strategy` to a section

**Step 1: Edit the settings file with custom setter**

```ruby
class MySettings
  VALID_MODES = %i[fast balanced thorough].freeze

  attr_reader :mode

  def initialize
    reset!
  end

  def mode=(value)
    normalized = value&.to_sym
    unless VALID_MODES.include?(normalized)
      raise ArgumentError, "Invalid mode #{value.inspect}. Must be one of: #{VALID_MODES.join(', ')}"
    end
    @mode = normalized
  end

  def reset!
    @mode = :balanced
  end
end
```

**Step 2: Write tests for all paths**

```ruby
test "mode defaults to balanced" do
  assert_equal :balanced, SourceMonitor.config.my_section.mode
end

test "mode accepts valid values" do
  %i[fast balanced thorough].each do |mode|
    SourceMonitor.configure do |config|
      config.my_section.mode = mode
    end
    assert_equal mode, SourceMonitor.config.my_section.mode
  end
end

test "mode accepts string values" do
  SourceMonitor.configure do |config|
    config.my_section.mode = "fast"
  end
  assert_equal :fast, SourceMonitor.config.my_section.mode
end

test "mode rejects invalid values" do
  assert_raises(ArgumentError, /Invalid mode/) do
    SourceMonitor.configure do |config|
      config.my_section.mode = :invalid
    end
  end
end
```

---

## Scenario C: Add Setting with Normalization

### Example: Numeric setting that normalizes edge cases

Follow the `ScrapingSettings` pattern:

```ruby
class MySettings
  DEFAULT_LIMIT = 50

  attr_reader :limit

  def initialize
    reset!
  end

  def limit=(value)
    @limit = normalize_numeric(value)
  end

  def reset!
    @limit = DEFAULT_LIMIT
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

**Test normalization edge cases:**

```ruby
test "limit normalizes string to integer" do
  SourceMonitor.configure { |c| c.my_section.limit = "10" }
  assert_equal 10, SourceMonitor.config.my_section.limit
end

test "limit normalizes nil to nil" do
  SourceMonitor.configure { |c| c.my_section.limit = nil }
  assert_nil SourceMonitor.config.my_section.limit
end

test "limit normalizes empty string to nil" do
  SourceMonitor.configure { |c| c.my_section.limit = "" }
  assert_nil SourceMonitor.config.my_section.limit
end

test "limit normalizes zero to nil" do
  SourceMonitor.configure { |c| c.my_section.limit = 0 }
  assert_nil SourceMonitor.config.my_section.limit
end

test "limit normalizes negative to nil" do
  SourceMonitor.configure { |c| c.my_section.limit = -5 }
  assert_nil SourceMonitor.config.my_section.limit
end
```

---

## Scenario D: Create a New Settings Section

### Step 1: Create the settings file

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

### Step 2: Add require and reader to Configuration

```ruby
# lib/source_monitor/configuration.rb

# At the top, add require:
require "source_monitor/configuration/notifications_settings"

# In the class:
attr_reader :http, :scrapers, :retention, :events, :models,
  :realtime, :fetching, :health, :authentication, :scraping,
  :notifications

# In initialize:
def initialize
  # ... existing ...
  @notifications = NotificationsSettings.new
end
```

### Step 3: Write tests

```ruby
# test/lib/source_monitor/configuration_test.rb

test "notifications settings have correct defaults" do
  settings = SourceMonitor.config.notifications
  assert_equal true, settings.enabled
  assert_equal [], settings.channels
  assert_equal 60, settings.throttle_seconds
end

test "notifications settings can be configured" do
  SourceMonitor.configure do |config|
    config.notifications.enabled = false
    config.notifications.channels = [:email]
    config.notifications.throttle_seconds = 30
  end

  settings = SourceMonitor.config.notifications
  assert_equal false, settings.enabled
  assert_equal [:email], settings.channels
  assert_equal 30, settings.throttle_seconds
end

test "notifications reset restores defaults" do
  SourceMonitor.configure do |config|
    config.notifications.enabled = false
  end
  SourceMonitor.reset_configuration!
  assert_equal true, SourceMonitor.config.notifications.enabled
end
```

### Step 4: Run tests

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb
```

---

## Checklist for Any New Setting

- [ ] Attribute added to settings class (attr_accessor or custom setter)
- [ ] Default value set in `reset!` (or `initialize` for classes without `reset!`)
- [ ] require statement added (if new file)
- [ ] Reader method exposed on Configuration (if new section)
- [ ] Initialization in Configuration#initialize (if new section)
- [ ] Tests: default value is correct
- [ ] Tests: value can be overridden
- [ ] Tests: reset restores default
- [ ] Tests: validation raises ArgumentError (if applicable)
- [ ] Tests: edge cases for normalization (if applicable)
- [ ] All tests pass: `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb`
- [ ] RuboCop clean: `bin/rubocop lib/source_monitor/configuration/`
