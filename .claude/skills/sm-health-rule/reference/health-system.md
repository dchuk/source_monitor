# Health System Reference

## System Registration

The health system registers itself during engine initialization via `Health.setup!`:

```ruby
module SourceMonitor
  module Health
    module_function

    def setup!
      register_fetch_callback
    end

    def fetch_callback
      @fetch_callback ||= lambda do |event|
        source = event&.source
        next unless source
        SourceHealthMonitor.new(source: source).call
      rescue StandardError => error
        log_error(source, error)
      end
    end

    def register_fetch_callback
      callbacks = SourceMonitor.config.events.callbacks_for(:after_fetch_completed)
      return if callbacks.include?(fetch_callback)
      SourceMonitor.config.events.after_fetch_completed(fetch_callback)
    end
  end
end
```

Key behaviors:
- Uses a memoized lambda to prevent duplicate registration
- Checks existing callbacks before adding
- Errors in the health callback are logged but don't crash the fetch pipeline

## SourceHealthMonitor Details

### Rolling Success Rate Calculation

```ruby
def calculate_success_rate(logs)
  successes = logs.count { |log| log.success? }
  total = logs.size
  return 0.0 if total.zero?
  (successes.to_f / total).round(4)
end
```

The rate is stored as a float (0.0 to 1.0) on `source.rolling_success_rate`.

### Minimum Sample Size

Thresholds only apply when the number of logs equals the configured `window_size`. This prevents premature auto-pausing of new sources:

```ruby
def thresholds_applicable?(sample_size)
  sample_size >= minimum_sample_size
end

def minimum_sample_size
  [config.window_size.to_i, 1].max
end
```

### Auto-Pause Algorithm

```
IF rate < auto_pause_threshold AND thresholds_active:
  new_until = now + auto_pause_cooldown_minutes
  IF existing_until > new_until:
    keep existing_until (don't shorten pause)
  ELSE:
    use new_until

  SET auto_paused_until = new_until
  SET auto_paused_at = now (or keep existing)
  PUSH next_fetch_at past pause window
  PUSH backoff_until past pause window
```

### Auto-Resume Algorithm

```
IF auto_paused_until IS NOT NULL AND rate >= auto_resume_threshold:
  CLEAR auto_paused_until
  CLEAR auto_paused_at
  CLEAR backoff_until
```

The resume threshold defaults to `max(auto_resume_threshold, auto_pause_threshold)` to prevent flapping.

### Consecutive Failure Detection

```ruby
def consecutive_failures(logs)
  logs.take_while { |log| !log_success?(log) }.size
end
```

Logs are ordered by `started_at DESC`, so `take_while` counts the most recent consecutive failures.

### Improving Streak Detection

```ruby
def improving_streak?(logs)
  success_streak = 0
  failure_seen = false
  logs.each do |log|
    if log_success?(log)
      success_streak += 1
    else
      failure_seen = true
      break
    end
  end
  success_streak >= 2 && failure_seen
end
```

A source is "improving" when it has >= 2 consecutive recent successes AND at least one failure exists in the window.

### Fixed Interval Enforcement

For non-adaptive sources, the monitor ensures `backoff_until` doesn't persist beyond what's needed:

```ruby
def enforce_fixed_interval(attrs, auto_paused_until)
  return if source.adaptive_fetching_enabled?
  return if auto_paused_active?(auto_paused_until)

  backoff_value = attrs.key?(:backoff_until) ? attrs[:backoff_until] : source.backoff_until
  return if backoff_value.blank?

  fixed_minutes = [source.fetch_interval_minutes.to_i, 1].max
  attrs[:next_fetch_at] = now + fixed_minutes.minutes
  attrs[:backoff_until] = nil
end
```

## Circuit Breaker vs Auto-Pause

These are two separate protection mechanisms:

| Feature | Circuit Breaker | Auto-Pause |
|---------|----------------|------------|
| **Scope** | Single fetch attempt | Rolling window |
| **Trigger** | RetryPolicy exhaustion | Success rate threshold |
| **Duration** | Error-type specific (1-2 hours) | Configurable cooldown (60 min default) |
| **Fields** | `fetch_circuit_*` | `auto_paused_*` |
| **Managed by** | RetryPolicy + SourceUpdater | SourceHealthMonitor |
| **Resets on** | Successful fetch | Success rate recovery |

### Circuit Breaker Flow

```
Error occurs -> RetryPolicy.decision
  -> retry? (attempts remaining)
     -> schedule retry with wait
  -> open_circuit? (attempts exhausted)
     -> set fetch_circuit_until
     -> FetchRunner skips fetch while circuit open
```

### Auto-Pause Flow

```
After every fetch -> SourceHealthMonitor.call
  -> calculate rolling success rate
  -> IF rate < threshold AND window full
     -> set auto_paused_until
     -> push next_fetch_at past pause window
```

## HealthCheckLog Model

```ruby
class HealthCheckLog < ApplicationRecord
  include SourceMonitor::Loggable

  belongs_to :source
  has_one :log_entry, as: :loggable, dependent: :destroy

  attribute :http_response_headers, default: -> { {} }
  validates :source, presence: true

  after_save :sync_log_entry  # Creates unified LogEntry record
end
```

Fields:
- `source_id` -- associated source
- `success` -- boolean
- `started_at`, `completed_at` -- timing
- `duration_ms` -- request duration
- `http_status` -- response status code
- `http_response_headers` -- response headers hash
- `error_class`, `error_message` -- error details

## Source Model Health Fields

From migration `20251012090000_add_health_fields_to_sources`:

```ruby
# Health status tracking
:health_status            # string, default: "healthy"
:health_status_changed_at # datetime
:rolling_success_rate     # float
:health_auto_pause_threshold # float (per-source override)

# Auto-pause state
:auto_paused_at           # datetime
:auto_paused_until        # datetime

# Circuit breaker state (fetch-level)
:fetch_retry_attempt      # integer, default: 0
:fetch_circuit_opened_at  # datetime
:fetch_circuit_until      # datetime

# Existing fields used by health system
:failure_count            # integer
:last_error               # string
:last_error_at            # datetime
:backoff_until            # datetime
:next_fetch_at            # datetime
:fetch_status             # string
```

## Source Model Health Methods

```ruby
def fetch_circuit_open?
  fetch_circuit_until.present? && fetch_circuit_until.future?
end

def auto_paused?
  auto_paused_until.present? && auto_paused_until.future?
end

def fetch_retry_attempt
  value = super
  value.present? ? value : 0
end
```

## Health Check Controllers

| Controller | Actions | Purpose |
|------------|---------|---------|
| `SourceHealthChecksController` | `create` | Trigger on-demand health check |
| `SourceHealthResetsController` | `create` | Reset all health state |
| `HealthController` | `show` | Engine health endpoint |

## Import Source Health Check

Used during OPML import to validate feed URLs before importing:

```ruby
result = Health::ImportSourceHealthCheck.new(feed_url: "https://example.com/feed.xml").call
```

- No Source record needed (works with raw URL)
- No conditional headers (no prior state)
- Returns simple Result: `status`, `error_message`, `http_status`
- Used by `ImportSessionHealthCheckJob` for batch validation
- Results stored in `import_session.parsed_sources[n]["health_status"]`
