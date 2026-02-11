---
name: rails-mailer
description: Generates ActionMailer classes with previews, parameterized mailers, and bundled notification patterns. Use when creating email notifications, mailer previews, digest emails, or when the user mentions mailers, emails, deliver_later, notifications, or email templates.
tools: Read, Write, Edit, Bash, Glob, Grep
---

# ActionMailer with Previews and Bundled Notifications

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

## Mailer File Structure

```
app/mailers/             # Mailer classes
app/views/layouts/mailer.html.erb   # Shared layout
app/views/user_mailer/   # Templates per mailer (HTML + text)
test/mailers/            # Mailer tests
test/mailers/previews/   # Browser previews (/rails/mailers)
```

## Basic Mailer Structure

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "notifications@example.com"
  layout "mailer"
  self.deliver_later_queue_name = :mailers
end

# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    @login_url = new_session_url
    mail(to: @user.email_address, subject: t(".subject", name: @user.name))
  end

  def password_reset(user)
    @user = user
    @reset_url = edit_password_url(token: @user.password_reset_token)
    mail(to: @user.email_address, subject: t(".subject"))
  end
end
```

### Templates (HTML + Text)

```erb
<%# app/views/user_mailer/welcome.html.erb %>
<h1><%= t(".greeting", name: @user.name) %></h1>
<p><%= t(".body") %></p>
<%= link_to t(".login_button"), @login_url %>
```

```text
<%# app/views/user_mailer/welcome.text.erb %>
<%= t(".greeting", name: @user.name) %>
<%= t(".body") %>
<%= t(".login_prompt") %>: <%= @login_url %>
```

Always provide both `.html.erb` and `.text.erb` templates. HTML-only emails trigger spam filters.

## Parameterized Mailers

Share setup logic across actions with `params`:

```ruby
# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  before_action :set_order
  before_action :set_user

  def confirmation
    mail(to: @user.email_address, subject: t(".subject", number: @order.number))
  end

  def shipped
    @tracking_url = @order.tracking_url
    mail(to: @user.email_address, subject: t(".subject", number: @order.number))
  end

  def cancelled
    mail(to: @user.email_address, subject: t(".subject", number: @order.number))
  end

  private

  def set_order = @order = params[:order]
  def set_user = @user = @order.user
end

# Usage:
OrderMailer.with(order: order).confirmation.deliver_later
```

## Mailer Previews

Previews render emails in the browser at `/rails/mailers`:

```ruby
# test/mailers/previews/user_mailer_preview.rb
class UserMailerPreview < ActionMailer::Preview
  def welcome
    UserMailer.welcome(User.first)
  end

  def password_reset
    user = User.first
    user.password_reset_token ||= SecureRandom.urlsafe_base64(20)
    UserMailer.password_reset(user)
  end
end

# test/mailers/previews/order_mailer_preview.rb
class OrderMailerPreview < ActionMailer::Preview
  def confirmation
    OrderMailer.with(order: Order.first).confirmation
  end

  def shipped
    OrderMailer.with(order: Order.where.not(tracking_url: nil).first || Order.first).shipped
  end
end
```

## Bundled Notification Pattern (Digest Emails)

Instead of one email per event, collect notifications and send in a batch.

### Notification Model

```ruby
# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true

  scope :undelivered, -> { where(delivered_at: nil) }
  scope :for_digest, -> { undelivered.where("created_at <= ?", Time.current) }

  def mark_delivered!
    update!(delivered_at: Time.current)
  end
end
```

### Digest Mailer

```ruby
# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  def digest(user, notifications)
    @user = user
    @notifications = notifications
    @grouped = notifications.group_by(&:notifiable_type)
    mail(to: @user.email_address, subject: t(".subject", count: notifications.size))
  end
end
```

### Recurring Digest Job

```ruby
# app/jobs/send_digest_emails_job.rb
class SendDigestEmailsJob < ApplicationJob
  queue_as :mailers

  def perform
    users_with_notifications.find_each do |user|
      notifications = user.notifications.for_digest.to_a
      next if notifications.empty?

      NotificationMailer.digest(user, notifications).deliver_now
      notifications.each(&:mark_delivered!)
    end
  end

  private

  def users_with_notifications
    User.where(id: Notification.undelivered.select(:user_id).distinct)
  end
end
```

```yaml
# config/recurring.yml
production:
  send_digest_emails:
    class: SendDigestEmailsJob
    schedule: every day at 8am
    queue: mailers
```

### Collecting Notifications

```ruby
# app/models/concerns/notifiable.rb
module Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :notifications, as: :notifiable, dependent: :destroy
  end

  def notify_users(users, type: self.class.name.underscore)
    users.each do |user|
      Notification.create!(user: user, notifiable: self, notification_type: type)
    end
  end
end
```

## Inline Attachments

```ruby
class ReportMailer < ApplicationMailer
  def monthly_report(account, report_data)
    @account = account
    attachments.inline["logo.png"] = File.read(Rails.root.join("app/assets/images/logo.png"))
    attachments["report.pdf"] = { mime_type: "application/pdf", content: generate_pdf(report_data) }
    mail(to: account_admin_email(account), subject: t(".subject"))
  end
end
```

## Integration with Solid Queue

```ruby
# In controllers/services — always deliver_later
UserMailer.welcome(user).deliver_later
OrderMailer.with(order: order).confirmation.deliver_later(queue: :critical)
NotificationMailer.digest(user, notifications).deliver_later(wait_until: Date.tomorrow.beginning_of_day)

# Inside background jobs — deliver_now is fine (already async)
class SendDigestEmailsJob < ApplicationJob
  def perform
    NotificationMailer.digest(user, notifications).deliver_now
  end
end
```

## I18n for Mailers

```yaml
# config/locales/mailers.en.yml
en:
  user_mailer:
    welcome:
      subject: "Welcome to %{name}!"
      greeting: "Hi %{name},"
      body: "Thanks for signing up."
    password_reset:
      subject: "Reset your password"
  order_mailer:
    confirmation:
      subject: "Order %{number} confirmed"
  notification_mailer:
    digest:
      subject:
        one: "You have 1 new notification"
        other: "You have %{count} new notifications"
```

## Testing Mailers with Minitest

```ruby
# test/mailers/user_mailer_test.rb
require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "welcome email" do
    user = users(:regular)
    email = UserMailer.welcome(user)

    assert_emails 1 do
      email.deliver_now
    end
    assert_equal [user.email_address], email.to
    assert_match "Welcome", email.subject
    assert_match user.name, email.body.encoded
  end
end

# test/mailers/order_mailer_test.rb
require "test_helper"

class OrderMailerTest < ActionMailer::TestCase
  test "confirmation email" do
    order = orders(:confirmed)
    email = OrderMailer.with(order: order).confirmation
    assert_equal [order.user.email_address], email.to
    assert_match order.number, email.subject
  end

  test "shipped email includes tracking URL" do
    order = orders(:shipped)
    email = OrderMailer.with(order: order).shipped
    assert_match order.tracking_url, email.body.encoded
  end
end

# test/controllers/registrations_controller_test.rb — integration
require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "sends welcome email on registration" do
    assert_enqueued_emails 1 do
      post registrations_url, params: {
        user: { name: "Test", email_address: "new@example.com", password: "password123" }
      }
    end
  end
end

# test/jobs/send_digest_emails_job_test.rb
require "test_helper"

class SendDigestEmailsJobTest < ActiveJob::TestCase
  test "sends digest to users with notifications" do
    assert_emails 1 do
      SendDigestEmailsJob.perform_now
    end
  end

  test "marks notifications as delivered" do
    SendDigestEmailsJob.perform_now
    assert_equal 0, Notification.undelivered.count
  end

  test "skips users with no notifications" do
    Notification.update_all(delivered_at: Time.current)
    assert_no_emails do
      SendDigestEmailsJob.perform_now
    end
  end
end
```

## Mailer Generation Checklist

- [ ] Mailer class inherits from `ApplicationMailer`
- [ ] Both HTML and text templates created
- [ ] I18n keys for subjects and body text
- [ ] Preview class in `test/mailers/previews/`
- [ ] Test covers recipients, subject, and body content
- [ ] `deliver_later` used in controllers (not `deliver_now`)
- [ ] Queue configured (defaults to `:mailers`)
- [ ] Digest pattern for high-frequency notifications

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| `deliver_now` in controllers | Blocks HTTP request | Use `deliver_later` |
| No text template | Spam filters flag HTML-only | Always provide `.text.erb` |
| No preview | Can't visually verify emails | Create preview class |
| Hardcoded strings | Can't translate | Use I18n |
| One email per event | Inbox flood | Use digest/bundled pattern |
| Business logic in mailer | Wrong layer | Keep in model/service |
