---
name: sm-job
description: Solid Queue job conventions for the SourceMonitor engine. Use when creating new background jobs, modifying existing jobs, configuring queues, or working with job scheduling and retry policies.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# SourceMonitor Job Development

## Overview

SourceMonitor uses Solid Queue (Rails 8 default) for background processing. All jobs inherit from `SourceMonitor::ApplicationJob` and use engine-namespaced queues.

## Queue Architecture

| Queue Role | Default Name | Jobs |
|------------|-------------|------|
| `:fetch` | `source_monitor_fetch` | FetchFeedJob, ScheduleFetchesJob, ItemCleanupJob, LogCleanupJob, SourceHealthCheckJob, ImportOpmlJob, ImportSessionHealthCheckJob |
| `:scrape` | `source_monitor_scrape` | ScrapeItemJob |

Queue names respect the host app's `ActiveJob::Base.queue_name_prefix` and `queue_name_delimiter`.

## Existing Jobs

| Job | Queue | Purpose | Pattern |
|-----|-------|---------|---------|
| `FetchFeedJob` | `:fetch` | Fetches a single source's feed | Delegates to `FetchRunner` |
| `ScheduleFetchesJob` | `:fetch` | Batch-enqueues due fetches | Delegates to `Scheduler.run` |
| `ScrapeItemJob` | `:scrape` | Scrapes a single item's URL | Delegates to `Scraping::ItemScraper` |
| `ItemCleanupJob` | `:fetch` | Prunes items by retention policy | Delegates to `RetentionPruner` |
| `LogCleanupJob` | `:fetch` | Removes old fetch/scrape logs | Direct SQL batches |
| `SourceHealthCheckJob` | `:fetch` | Runs health check on a source | Delegates to `Health::SourceHealthCheck` |
| `ImportOpmlJob` | `:fetch` | Imports sources from OPML | Delegates to source creation |
| `ImportSessionHealthCheckJob` | `:fetch` | Health-checks import candidates | Delegates to `Health::ImportSourceHealthCheck` |

## Key Conventions

### 1. Shallow Jobs

Jobs contain **only** deserialization + delegation. No business logic lives in job classes.

```ruby
# CORRECT -- shallow delegation
def perform(source_id)
  source = SourceMonitor::Source.find_by(id: source_id)
  return unless source
  SourceMonitor::Fetching::FetchRunner.new(source: source).run
end

# WRONG -- business logic in job
def perform(source_id)
  source = SourceMonitor::Source.find(source_id)
  response = Faraday.get(source.feed_url)  # Don't do this
  feed = Feedjira.parse(response.body)      # Business logic belongs elsewhere
end
```

### 2. Queue Declaration

Use the `source_monitor_queue` class method (not `queue_as`):

```ruby
class MyJob < SourceMonitor::ApplicationJob
  source_monitor_queue :fetch  # Uses SourceMonitor.queue_name(:fetch)
end
```

This ensures the queue name respects engine configuration and host app prefixes.

### 3. ID-Based Arguments

Pass record IDs, not Active Record objects. Guard against missing records:

```ruby
def perform(source_id)
  source = SourceMonitor::Source.find_by(id: source_id)
  return unless source  # Silently skip if deleted
  # ...
end
```

### 4. Error Handling

Use ActiveJob's built-in error handling:

```ruby
discard_on ActiveJob::DeserializationError  # Record deleted between enqueue and perform
retry_on SomeTransientError, wait: 30.seconds, attempts: 5
```

### 5. Logging Pattern

Use structured logging with a consistent format:

```ruby
def log(stage, **extra)
  return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
  payload = { stage: "SourceMonitor::MyJob##{stage}", **extra }.compact
  Rails.logger.info("[SourceMonitor::MyJob] #{payload.to_json}")
rescue StandardError
  nil
end
```

## Creating a New Job

### Template

```ruby
# app/jobs/source_monitor/my_new_job.rb
# frozen_string_literal: true

module SourceMonitor
  class MyNewJob < ApplicationJob
    source_monitor_queue :fetch  # or :scrape

    discard_on ActiveJob::DeserializationError

    def perform(record_id)
      record = SourceMonitor::Source.find_by(id: record_id)
      return unless record

      # Delegate to a service/model method
      SourceMonitor::MyService.new(record: record).call
    end
  end
end
```

### Steps

1. Create file at `app/jobs/source_monitor/my_new_job.rb`
2. Inherit from `SourceMonitor::ApplicationJob`
3. Call `source_monitor_queue` with `:fetch` or `:scrape`
4. Add `discard_on ActiveJob::DeserializationError`
5. Accept IDs as arguments, guard with `find_by`
6. Delegate to service/model -- no business logic in the job
7. Write tests in `test/jobs/source_monitor/my_new_job_test.rb`

## Queue Configuration

### Engine Configuration

```ruby
SourceMonitor.configure do |config|
  config.queue_namespace = "source_monitor"        # Base namespace
  config.fetch_queue_name = "source_monitor_fetch"  # Fetch queue name
  config.scrape_queue_name = "source_monitor_scrape" # Scrape queue name
  config.fetch_queue_concurrency = 2                # Concurrent fetch workers
  config.scrape_queue_concurrency = 2               # Concurrent scrape workers
end
```

### Queue Name Resolution

```ruby
SourceMonitor.queue_name(:fetch)  # => "source_monitor_fetch"
# With host app prefix "myapp":   => "myapp_source_monitor_fetch"
```

### Recurring Jobs

The install generator (`bin/rails generate source_monitor:install`) automatically configures these recurring jobs in `config/recurring.yml`:

| Job | Schedule |
|-----|----------|
| `SourceMonitor::ScheduleFetchesJob` | every minute |
| `SourceMonitor::Scraping::Scheduler.run` | every 2 minutes |
| `SourceMonitor::ItemCleanupJob` | at 2am every day |
| `SourceMonitor::LogCleanupJob` | at 3am every day |

The install generator automatically configures `config/recurring.yml` with these entries AND patches the `config/queue.yml` dispatcher with `recurring_schedule: config/recurring.yml` so recurring jobs load on startup. Both steps are idempotent. If you need to customize schedules, edit `config/recurring.yml` directly.

## Retry Policies

FetchFeedJob uses a custom retry strategy via `RetryPolicy`:

| Error Type | Retry Attempts | Wait | Circuit Breaker |
|------------|---------------|------|-----------------|
| Timeout | 2 | 2 min | 1 hour |
| Connection | 3 | 5 min | 1 hour |
| HTTP 429 | 2 | 15 min | 90 min |
| HTTP 5xx | 2 | 10 min | 90 min |
| HTTP 4xx | 1 | 45 min | 2 hours |
| Parsing | 1 | 30 min | 2 hours |
| Unexpected | 1 | 30 min | 2 hours |

## CleanupOptions Helper

`SourceMonitor::Jobs::CleanupOptions` normalizes job arguments for cleanup jobs:

```ruby
options = CleanupOptions.normalize(options)  # Symbolize keys, handle nil
now = CleanupOptions.resolve_time(options[:now])  # Parse time strings
ids = CleanupOptions.extract_ids(options[:source_ids])  # Flatten/parse IDs
batch_size = CleanupOptions.batch_size(options, default: 100)  # Safe integer
```

## Testing

### Test Template

```ruby
# test/jobs/source_monitor/my_new_job_test.rb
# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class MyNewJobTest < ActiveJob::TestCase
    setup do
      @source = create_source!
    end

    test "performs work for valid source" do
      # Stub external calls
      MyService.any_instance.expects(:call).once

      MyNewJob.perform_now(@source.id)
    end

    test "silently skips missing source" do
      assert_nothing_raised do
        MyNewJob.perform_now(-1)
      end
    end

    test "enqueues on correct queue" do
      assert_enqueued_with(job: MyNewJob, queue: SourceMonitor.queue_name(:fetch).to_s) do
        MyNewJob.perform_later(@source.id)
      end
    end
  end
end
```

### Testing Enqueue from Models

```ruby
test "fetching enqueues via FetchRunner.enqueue" do
  with_inline_jobs do
    stub_request(:get, source.feed_url).to_return(status: 200, body: feed_xml)
    SourceMonitor::Fetching::FetchRunner.enqueue(source)
  end
end
```

## Checklist

- [ ] Job inherits from `SourceMonitor::ApplicationJob`
- [ ] Uses `source_monitor_queue` (not `queue_as`)
- [ ] Accepts IDs, not AR objects
- [ ] Guards with `find_by` + early return
- [ ] No business logic in the job class
- [ ] `discard_on ActiveJob::DeserializationError`
- [ ] Error handling with `retry_on` where appropriate
- [ ] Test covers perform, missing record, and queue assignment
- [ ] All tests GREEN

## References

- `app/jobs/source_monitor/` -- All engine jobs
- `lib/source_monitor/jobs/` -- Job support classes (CleanupOptions, Visibility, SolidQueueMetrics)
- `lib/source_monitor/configuration.rb` -- Queue configuration
- `test/jobs/source_monitor/` -- Job tests
