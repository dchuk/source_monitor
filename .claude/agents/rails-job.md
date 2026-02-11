---
name: rails-job
description: Generates shallow Solid Queue background jobs with _later/_now naming conventions. Use when creating background jobs, async processing, recurring tasks, or when the user mentions jobs, queues, background work, deliver_later, perform_later, or Solid Queue.
tools: Read, Write, Edit, Bash, Glob, Grep
---

# Solid Queue Background Jobs

## Project Conventions
- **Testing:** Minitest + fixtures (NEVER RSpec or FactoryBot)
- **Components:** ViewComponents for reusable UI (partials OK for simple one-offs)
- **Authorization:** Pundit policies (deny by default)
- **Jobs:** Solid Queue, shallow jobs, `_later`/`_now` naming
- **Frontend:** Hotwire (Turbo + Stimulus) + Tailwind CSS
- **State:** State-as-records for business state (booleans only for technical flags)
- **Architecture:** Rich models first, service objects for multi-model orchestration
- **Routing:** Everything-is-CRUD (new resource over new action)
- **Quality:** RuboCop (omakase) + Brakeman

## Shallow Job Philosophy

Jobs are **thin dispatchers**, not business logic containers. A job should:
1. Deserialize arguments (find records by ID)
2. Delegate to a model method or service object
3. Nothing else

```ruby
# GOOD: Shallow job — delegates immediately
class FulfillOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    order.fulfill!
  end
end

# BAD: Fat job — business logic lives in the job
class FulfillOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    order.update!(status: :fulfilled)
    order.line_items.each { |li| li.product.decrement!(:stock) }
    OrderMailer.fulfilled(order).deliver_later
    order.account.update_stats!
  end
end
```

## `_later` / `_now` Naming Convention

Expose async operations on models and services:

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  def fulfill!
    transaction do
      update!(fulfilled_at: Time.current)
      line_items.each { |li| li.product.decrement!(:stock) }
    end
    OrderMailer.fulfilled(self).deliver_later
  end

  def fulfill_later
    FulfillOrderJob.perform_later(id)
  end
end

# app/services/reports/generate_service.rb
module Reports
  class GenerateService
    def call(account:, date_range:, format:)
      data = gather_data(account, date_range)
      Result.success(compile_report(data, format))
    rescue StandardError => e
      Result.failure(e.message)
    end

    def self.generate_later(account_id:, date_range:, format:)
      GenerateReportJob.perform_later(account_id, date_range.to_json, format)
    end

    def self.generate_now(account:, date_range:, format:)
      new.call(account: account, date_range: date_range, format: format)
    end
  end
end
```

## ApplicationJob Base Class

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 10
  discard_on ActiveJob::DeserializationError
end
```

## Solid Queue Configuration

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue

# config/environments/test.rb
config.active_job.queue_adapter = :test
```

### Queue Priority

| Queue | Priority | Use For |
|-------|----------|---------|
| `critical` | Highest | Payment processing, auth tokens |
| `default` | Normal | Standard business operations |
| `mailers` | Normal | Email delivery |
| `low` | Low | Reports, analytics, cleanup |

### Recurring Jobs

```yaml
# config/recurring.yml
production:
  cleanup_expired_sessions:
    class: CleanupExpiredSessionsJob
    schedule: every day at 3am
    queue: low

  send_daily_digest:
    class: SendDailyDigestJob
    schedule: every day at 8am
    queue: mailers

  sync_inventory:
    class: SyncInventoryJob
    schedule: every 15 minutes
    queue: default
```

## Error Handling and Retries

```ruby
class SyncInventoryJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::ConnectionFailed, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(product_id)
    product = Product.find(product_id)
    ExternalInventoryApi.sync(product)
  end
end

class ProcessPaymentJob < ApplicationJob
  queue_as :critical

  retry_on PaymentGateway::TemporaryError, wait: 10.seconds, attempts: 3
  discard_on PaymentGateway::InvalidCard

  after_discard do |job, error|
    order = Order.find(job.arguments.first)
    order.mark_payment_failed!(error: error.message)
    AdminMailer.payment_failure(order, error).deliver_later
  end

  def perform(order_id)
    order = Order.find(order_id)
    Payments::ChargeService.new.call(order: order)
  end
end
```

## Common Job Patterns

### Notification Delivery

```ruby
class DeliverNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find(notification_id)
    notification.deliver!
  end
end
```

### Data Cleanup

```ruby
class CleanupExpiredSessionsJob < ApplicationJob
  queue_as :low

  def perform
    Session.expired.in_batches(of: 1000).delete_all
  end
end
```

### Report Generation

```ruby
class GenerateReportJob < ApplicationJob
  queue_as :low

  def perform(account_id, date_range_json, format)
    account = Account.find(account_id)
    date_range = JSON.parse(date_range_json)

    result = Reports::GenerateService.new.call(
      account: account,
      date_range: Date.parse(date_range["start"])..Date.parse(date_range["end"]),
      format: format
    )

    if result.success?
      ReportMailer.completed(account, result.data).deliver_later
    else
      ReportMailer.failed(account, result.error).deliver_later
    end
  end
end
```

### Broadcast Updates

```ruby
class BroadcastDashboardUpdateJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find(account_id)
    stats = DashboardStatsQuery.new(account: account).call

    Turbo::StreamsChannel.broadcast_replace_to(
      account, target: "dashboard_stats",
      partial: "dashboards/stats", locals: { stats: stats }
    )
  end
end
```

## Job Arguments Best Practices

```ruby
# GOOD: Pass serializable IDs
FulfillOrderJob.perform_later(order.id)

# BAD: Complex nested structures
GenerateReportJob.perform_later({ account: account, options: { format: :pdf } })
```

- Pass IDs, not ActiveRecord objects (explicit, avoids stale data)
- Keep arguments simple (strings, integers, arrays of scalars)
- Find records inside `perform` to get fresh data

## Testing Jobs with Minitest

```ruby
# test/jobs/fulfill_order_job_test.rb
require "test_helper"

class FulfillOrderJobTest < ActiveJob::TestCase
  test "fulfills the order" do
    order = orders(:pending)
    FulfillOrderJob.perform_now(order.id)
    assert_not_nil order.reload.fulfilled_at
  end

  test "is enqueued to default queue" do
    assert_equal "default", FulfillOrderJob.new.queue_name
  end
end

# test/models/order_test.rb — testing _later convenience
require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "#fulfill_later enqueues the job" do
    order = orders(:pending)
    assert_enqueued_with(job: FulfillOrderJob, args: [order.id]) do
      order.fulfill_later
    end
  end
end

# test/controllers/orders_controller_test.rb — testing integration
require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues fulfillment job" do
    sign_in_as users(:regular)
    assert_enqueued_with(job: FulfillOrderJob) do
      post orders_url, params: { order: { product_id: products(:widget).id } }
    end
  end

  test "inline execution fulfills order" do
    sign_in_as users(:regular)
    perform_enqueued_jobs do
      post orders_url, params: { order: { product_id: products(:widget).id } }
    end
    assert_not_nil Order.last.fulfilled_at
  end
end
```

## Job Generation Checklist

- [ ] Job class inherits from `ApplicationJob`
- [ ] Job is shallow (deserialize + delegate only)
- [ ] Queue set appropriately (`critical`, `default`, `low`)
- [ ] `retry_on` for transient failures (network, deadlocks)
- [ ] `discard_on` for permanent failures (deleted records)
- [ ] Model has `_later` convenience method
- [ ] Arguments are simple (IDs, strings)
- [ ] Test covers `perform_now` behavior
- [ ] Test covers enqueuing with `assert_enqueued_with`
- [ ] Recurring job added to `config/recurring.yml` if scheduled

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Fat job | Business logic in `perform` | Delegate to model/service |
| Passing AR objects | Stale data, serialization overhead | Pass IDs, find in `perform` |
| No retry strategy | Transient failures kill jobs | `retry_on` for known errors |
| No error handling | Silent failures | `discard_on`, `after_discard` |
| Long-running job | Blocks queue workers | Break into smaller jobs |
| Missing `_later` method | Callers create jobs directly | Add convenience method |
