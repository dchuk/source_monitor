---
name: solid-queue-setup
description: Configures Solid Queue for background jobs in Rails 8. Use when setting up background processing, creating background jobs, configuring job queues, recurring jobs, or migrating from Sidekiq to Solid Queue.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Solid Queue Setup for Rails 8

## Overview

Solid Queue is Rails 8's default Active Job backend:
- Database-backed (no Redis required)
- Built-in concurrency controls
- Supports priorities and multiple queues
- Web UI available via Mission Control

## Quick Start

```bash
bundle add solid_queue
bin/rails solid_queue:install
bin/rails db:migrate
```

### Configuration

```yaml
# config/solid_queue.yml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 1
      polling_interval: 0.1

development:
  <<: *default

production:
  <<: *default
  workers:
    - queues: [critical, default]
      threads: 5
      processes: 2
    - queues: [low]
      threads: 2
      processes: 1
```

### Set as Active Job Adapter

```ruby
# config/application.rb
config.active_job.queue_adapter = :solid_queue
```

## Naming Convention

Use `_later` for async, `_now` for synchronous:

```ruby
# Async (queued via Solid Queue) - preferred
SendWelcomeEmailJob.perform_later(user.id)

# Synchronous (runs immediately, skips queue) - use sparingly
SendWelcomeEmailJob.perform_now(user.id)
```

## Creating Jobs

### Basic Job

```ruby
# app/jobs/send_welcome_email_job.rb
class SendWelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome(user).deliver_now
  end
end
```

### Job with Retries

```ruby
# app/jobs/process_payment_job.rb
class ProcessPaymentJob < ApplicationJob
  queue_as :critical

  retry_on PaymentGatewayError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  rescue_from(StandardError) do |exception|
    ErrorNotifier.notify(exception)
    raise
  end

  def perform(order_id)
    order = Order.find(order_id)
    PaymentService.new.charge(order)
  end
end
```

### Job with Priority

```ruby
class UrgentNotificationJob < ApplicationJob
  queue_as :critical

  # Lower number = higher priority (default is 0)
  def priority
    -10
  end

  def perform(notification_id)
    notification = Notification.find(notification_id)
    notification.deliver!
  end
end
```

## Enqueueing Jobs

```ruby
# Enqueue immediately
SendWelcomeEmailJob.perform_later(user.id)

# Enqueue with delay
SendReminderJob.set(wait: 1.hour).perform_later(user.id)

# Enqueue at specific time
SendReportJob.set(wait_until: Date.tomorrow.noon).perform_later

# Enqueue on specific queue
ProcessJob.set(queue: :low).perform_later(data)
```

## Recurring Jobs

```yaml
# config/recurring.yml
production:
  daily_report:
    class: GenerateDailyReportJob
    schedule: every day at 6am
    queue: low

  cleanup:
    class: CleanupOldRecordsJob
    schedule: every sunday at 2am

  sync:
    class: SyncExternalDataJob
    schedule: every 15 minutes

  session_cleanup:
    class: SessionCleanupJob
    schedule: every day at 3am
```

## Testing Jobs

### Job Test Template

```ruby
# test/jobs/send_welcome_email_job_test.rb
require "test_helper"

class SendWelcomeEmailJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
  end

  test "sends welcome email" do
    assert_enqueued_emails 1 do
      SendWelcomeEmailJob.perform_now(@user.id)
    end
  end

  test "enqueues on default queue" do
    assert_enqueued_with(job: SendWelcomeEmailJob, queue: "default") do
      SendWelcomeEmailJob.perform_later(@user.id)
    end
  end
end
```

### Testing Enqueueing

```ruby
# test/jobs/process_payment_job_test.rb
require "test_helper"

class ProcessPaymentJobTest < ActiveJob::TestCase
  test "enqueues the job with correct arguments" do
    order = orders(:one)

    assert_enqueued_with(job: ProcessPaymentJob, args: [order.id]) do
      ProcessPaymentJob.perform_later(order.id)
    end
  end

  test "enqueues on critical queue" do
    assert_enqueued_with(job: ProcessPaymentJob, queue: "critical") do
      ProcessPaymentJob.perform_later(orders(:one).id)
    end
  end
end
```

### Testing Job Side Effects

```ruby
# test/jobs/cleanup_old_records_job_test.rb
require "test_helper"

class CleanupOldRecordsJobTest < ActiveJob::TestCase
  test "deletes old sessions" do
    old_session = sessions(:old)
    old_session.update!(created_at: 31.days.ago)
    recent_session = sessions(:one)

    CleanupOldRecordsJob.perform_now

    assert_not Session.exists?(old_session.id)
    assert Session.exists?(recent_session.id)
  end
end
```

### Testing with perform_enqueued_jobs

```ruby
# test/integration/signup_flow_test.rb
require "test_helper"

class SignupFlowTest < ActionDispatch::IntegrationTest
  test "signup sends welcome email" do
    perform_enqueued_jobs do
      post signups_path, params: {
        signup: { email: "new@example.com", name: "Test" }
      }
    end

    assert_emails 1
  end
end
```

## Running Solid Queue

```bash
# Development
bin/rails solid_queue:start

# Production (Procfile)
web: bin/rails server
worker: bin/rails solid_queue:start
```

## Monitoring

### Mission Control (Web UI)

```ruby
# Gemfile
gem "mission_control-jobs"

# config/routes.rb
mount MissionControl::Jobs::Engine, at: "/jobs"
```

### Console Queries

```ruby
SolidQueue::Job.where(finished_at: nil).count        # Pending
SolidQueue::FailedExecution.count                      # Failed
SolidQueue::FailedExecution.last.retry                 # Retry
SolidQueue::Job.where("finished_at < ?", 1.week.ago).delete_all  # Cleanup
```

## Migration from Sidekiq

| Sidekiq | Solid Queue |
|---------|-------------|
| `perform_async(args)` | `perform_later(args)` |
| `perform_in(5.minutes, args)` | `set(wait: 5.minutes).perform_later(args)` |
| `sidekiq_options queue: 'critical'` | `queue_as :critical` |
| `sidekiq_retry_in` | `retry_on` with `wait:` |

## Checklist

- [ ] Solid Queue gem installed
- [ ] Migrations run
- [ ] Queue adapter configured
- [ ] Jobs use `perform_later` (not `perform_now`)
- [ ] Error handling with `retry_on` / `discard_on`
- [ ] Recurring jobs configured
- [ ] Job tests written
- [ ] Mission Control mounted (optional)
- [ ] All tests GREEN
