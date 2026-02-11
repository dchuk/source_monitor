---
name: sm-health-rule
description: Health status rules, circuit breaker, and auto-pause logic for SourceMonitor sources. Use when working with health checks, health status transitions, auto-pause thresholds, circuit breaker behavior, or adding new health rules.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
disable-model-invocation: true
---

# SourceMonitor Health Rule Development

## Overview

The health system monitors source reliability by tracking fetch success rates and automatically pausing unreliable sources. It consists of three main components:

1. **SourceHealthMonitor** -- evaluates rolling success rate, determines health status, triggers auto-pause/resume
2. **SourceHealthCheck** -- performs on-demand HTTP health checks
3. **SourceHealthReset** -- resets all health state for a source

## Architecture

```
Health Module (setup!)
  |
  +-- Registers callback: after_fetch_completed -> SourceHealthMonitor
  |
  +-- SourceHealthMonitor (per-fetch evaluation)
  |     +-- Reads recent fetch_logs
  |     +-- Calculates rolling_success_rate
  |     +-- Determines health_status
  |     +-- Triggers auto-pause / auto-resume
  |
  +-- SourceHealthCheck (on-demand)
  |     +-- HTTP GET to feed_url
  |     +-- Creates HealthCheckLog record
  |     +-- Returns Result struct
  |
  +-- SourceHealthReset (manual reset)
        +-- Clears all health state
        +-- Resets to "healthy" status
```

## Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `lib/source_monitor/health.rb` | Module entry point, callback registration | 47 |
| `lib/source_monitor/health/source_health_monitor.rb` | Rolling success rate + status + auto-pause | 210 |
| `lib/source_monitor/health/source_health_check.rb` | On-demand HTTP health check | 100 |
| `lib/source_monitor/health/source_health_reset.rb` | Reset all health state | 68 |
| `lib/source_monitor/health/import_source_health_check.rb` | Health check for import candidates | 55 |
| `lib/source_monitor/configuration/health_settings.rb` | Configuration defaults | 27 |
| `app/models/source_monitor/health_check_log.rb` | Health check log record | 28 |
| `app/jobs/source_monitor/source_health_check_job.rb` | Background health check job | 77 |

## Health Status Values

| Status | Meaning | Trigger |
|--------|---------|---------|
| `healthy` | Source is reliable | success_rate >= healthy_threshold (0.8) |
| `warning` | Some failures occurring | success_rate >= warning_threshold (0.5) but < healthy |
| `critical` | High failure rate | success_rate < warning_threshold |
| `declining` | Consecutive failures | >= 3 consecutive failures in recent logs |
| `improving` | Recovery in progress | >= 2 consecutive successes after a failure |
| `auto_paused` | Automatically paused | success_rate < auto_pause_threshold (0.2) |

### Status Priority (highest to lowest)

```
auto_paused > declining > improving > healthy > warning > critical
```

Determination logic:

```ruby
def determine_status(rate, auto_paused_until, logs)
  if auto_paused_active?(auto_paused_until)
    "auto_paused"
  elsif consecutive_failures(logs) >= 3
    "declining"
  elsif improving_streak?(logs)
    "improving"
  elsif rate >= healthy_threshold
    "healthy"
  elsif rate >= warning_threshold
    "warning"
  else
    "critical"
  end
end
```

## Health Configuration

### Default Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `window_size` | 20 | Number of recent fetch logs to evaluate |
| `healthy_threshold` | 0.8 | Success rate for "healthy" status |
| `warning_threshold` | 0.5 | Success rate for "warning" status |
| `auto_pause_threshold` | 0.2 | Below this, source is auto-paused |
| `auto_resume_threshold` | 0.6 | Above this, auto-pause is lifted |
| `auto_pause_cooldown_minutes` | 60 | Minimum pause duration |

### Per-Source Override

Sources can override `health_auto_pause_threshold` (validated 0-1 range):

```ruby
source.health_auto_pause_threshold = 0.3  # More tolerant than default 0.2
```

### Configuration Access

```ruby
SourceMonitor.configure do |config|
  config.health.window_size = 30
  config.health.auto_pause_threshold = 0.15
  config.health.auto_pause_cooldown_minutes = 120
end
```

## SourceHealthMonitor

### How It Works

The monitor runs automatically after every fetch via the `after_fetch_completed` event callback.

**Step 1: Gather Data**
```ruby
logs = source.fetch_logs.order(started_at: :desc).limit(window_size)
rate = successes.to_f / total
```

**Step 2: Check Thresholds**

Thresholds only apply when `logs.size >= window_size` (minimum sample size).

**Step 3: Auto-Resume Check**

If source is currently auto-paused and success rate >= `auto_resume_threshold`:
- Clear `auto_paused_until` and `auto_paused_at`
- Clear `backoff_until`

**Step 4: Auto-Pause Check**

If success rate < `auto_pause_threshold`:
- Set `auto_paused_until` to `now + cooldown_minutes`
- Set `auto_paused_at` to now (or keep existing)
- Push `next_fetch_at` and `backoff_until` past the pause window

**Step 5: Fixed Interval Enforcement**

For non-adaptive sources that are not paused, clear `backoff_until` and reset `next_fetch_at` to the fixed interval.

**Step 6: Apply Status**

Only updates `health_status` and `health_status_changed_at` when the status actually changes.

### Source Fields Updated

| Field | Type | Purpose |
|-------|------|---------|
| `health_status` | string | Current health status |
| `health_status_changed_at` | datetime | When status last changed |
| `rolling_success_rate` | float | Current success rate (0.0-1.0) |
| `auto_paused_at` | datetime | When auto-pause was triggered |
| `auto_paused_until` | datetime | When auto-pause expires |
| `health_auto_pause_threshold` | float | Per-source override |

## Circuit Breaker (Fetch-Level)

Separate from health status, the fetch pipeline has its own circuit breaker via `RetryPolicy`:

| Field | Purpose |
|-------|---------|
| `fetch_retry_attempt` | Current retry count |
| `fetch_circuit_opened_at` | When circuit was opened |
| `fetch_circuit_until` | When circuit closes |

```ruby
def fetch_circuit_open?
  fetch_circuit_until.present? && fetch_circuit_until.future?
end
```

Circuit breaker is managed by `RetryPolicy` in `SourceUpdater` and `FetchFeedJob`. It is distinct from the health system's auto-pause.

## SourceHealthCheck

On-demand HTTP check that creates a `HealthCheckLog`:

```ruby
result = SourceMonitor::Health::SourceHealthCheck.new(source: source).call
result.success?  # => true/false
result.log       # => HealthCheckLog record
result.error     # => exception if failed
```

Features:
- Uses source's custom headers and conditional request headers (ETag, If-Modified-Since)
- HTTP 200-399 is considered successful
- Creates a HealthCheckLog record regardless of outcome
- Does NOT update health status (that's the monitor's job)

## SourceHealthReset

Manually resets all health state to defaults:

```ruby
SourceMonitor::Health::SourceHealthReset.call(source: source)
```

Resets:
- `health_status` -> "healthy"
- `auto_paused_at`, `auto_paused_until` -> nil
- `rolling_success_rate` -> nil
- `failure_count` -> 0
- `last_error`, `last_error_at` -> nil
- `backoff_until` -> nil
- `fetch_status` -> "idle"
- `fetch_retry_attempt` -> 0
- `fetch_circuit_opened_at`, `fetch_circuit_until` -> nil
- `next_fetch_at` -> calculated from fetch_interval_minutes

Uses `with_lock` for concurrency safety.

## ImportSourceHealthCheck

Lightweight health check for import candidates (no Source record needed):

```ruby
result = Health::ImportSourceHealthCheck.new(feed_url: url).call
result.status        # => "healthy" or "unhealthy"
result.error_message # => nil or error description
result.http_status   # => HTTP status code
```

## Adding a New Health Rule

To add a new condition that affects health status:

### Step 1: Define the Rule

Add a method to `SourceHealthMonitor`:

```ruby
def my_custom_condition?(logs)
  # Evaluate logs or source state
  # Return true if condition is met
end
```

### Step 2: Integrate into Status Determination

Add the condition to `determine_status`:

```ruby
def determine_status(rate, auto_paused_until, logs)
  if auto_paused_active?(auto_paused_until)
    "auto_paused"
  elsif my_custom_condition?(logs)  # Add here
    "my_custom_status"
  elsif consecutive_failures(logs) >= 3
    "declining"
  # ...
end
```

### Step 3: Add Configuration

If the rule needs a threshold, add it to `HealthSettings`:

```ruby
class HealthSettings
  attr_accessor :my_threshold
  def reset!
    @my_threshold = 0.5  # default
    # ...
  end
end
```

### Step 4: Update Source Model

If adding a new status value, ensure views and helpers handle it.

### Step 5: Write Tests

```ruby
test "source enters my_custom_status when condition met" do
  source = create_source!
  # Create fetch logs that trigger the condition
  monitor = SourceMonitor::Health::SourceHealthMonitor.new(source: source)
  monitor.call
  assert_equal "my_custom_status", source.reload.health_status
end
```

## Testing

- Health monitor tests: `test/lib/source_monitor/health/source_health_monitor_test.rb`
- Health check tests: `test/lib/source_monitor/health/source_health_check_test.rb`
- Health reset tests: `test/lib/source_monitor/health/source_health_reset_test.rb`
- Health module tests: `test/lib/source_monitor/health/health_module_test.rb`
- Health check job tests: `test/jobs/source_monitor/source_health_check_job_test.rb`
- Controller tests: `test/controllers/source_monitor/source_health_checks_controller_test.rb`

Use `PARALLEL_WORKERS=1` for single test files to avoid PG segfault.

## Checklist

- [ ] New health rules evaluate from `fetch_logs` (rolling window)
- [ ] Thresholds are configurable via `HealthSettings`
- [ ] Per-source overrides supported where appropriate
- [ ] Status transitions only fire when status actually changes
- [ ] Auto-pause cooldown prevents flapping
- [ ] Tests cover threshold boundaries and edge cases
- [ ] Health status values handled in views/helpers

## References

- `lib/source_monitor/health/` -- All health system code
- `lib/source_monitor/configuration/health_settings.rb` -- Configuration
- `app/models/source_monitor/source.rb` -- Source health fields
- `app/models/source_monitor/health_check_log.rb` -- Health check log model
- `app/jobs/source_monitor/source_health_check_job.rb` -- Background health check
- `test/lib/source_monitor/health/` -- Health system tests
