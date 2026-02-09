---
name: action-mailer-patterns
description: Implements transactional emails with Action Mailer and TDD. Use when creating email templates, notification emails, password resets, email previews, or when user mentions mailer, email, notifications, or transactional emails.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Action Mailer Patterns for Rails 8

## Overview

Action Mailer handles transactional emails:
- HTML and text email templates
- Layouts for consistent styling
- Previews for development
- Background delivery via Active Job (Solid Queue)
- Internationalized emails

## Quick Start

```bash
bin/rails generate mailer User welcome password_reset
```

## Configuration

```ruby
# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

# config/environments/production.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.default_url_options = { host: "example.com" }
```

### Application Mailer

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@example.com"
  layout "mailer"

  helper_method :app_name

  private

  def app_name
    Rails.application.class.module_parent_name
  end
end
```

## TDD Workflow

```
Mailer Progress:
- [ ] Step 1: Write mailer test (RED)
- [ ] Step 2: Run test (fails)
- [ ] Step 3: Create mailer method
- [ ] Step 4: Create email templates
- [ ] Step 5: Run test (GREEN)
- [ ] Step 6: Create preview
```

## Testing Mailers (Minitest)

### Mailer Test

```ruby
# test/mailers/user_mailer_test.rb
require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
  end

  test "welcome email renders headers" do
    mail = UserMailer.welcome(@user)

    assert_equal I18n.t("user_mailer.welcome.subject"), mail.subject
    assert_equal [@user.email_address], mail.to
    assert_equal ["noreply@example.com"], mail.from
  end

  test "welcome email renders HTML body" do
    mail = UserMailer.welcome(@user)

    assert_includes mail.html_part.body.to_s, @user.name
    assert_includes mail.html_part.body.to_s, "Welcome"
  end

  test "welcome email renders text body" do
    mail = UserMailer.welcome(@user)

    assert_includes mail.text_part.body.to_s, @user.name
  end

  test "welcome email includes login link" do
    mail = UserMailer.welcome(@user)

    assert_includes mail.html_part.body.to_s, new_session_url
  end

  test "password_reset email includes token" do
    token = "reset-token-123"
    mail = UserMailer.password_reset(@user, token)

    assert_equal [@user.email_address], mail.to
    assert_includes mail.html_part.body.to_s, token
  end
end
```

### Testing Delivery

```ruby
# test/integration/registration_test.rb
require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  test "registration sends welcome email" do
    assert_enqueued_email_with UserMailer, :welcome do
      post registrations_path, params: {
        registration: { email: "new@example.com", name: "Test", password: "password123" }
      }
    end
  end
end
```

### Testing with perform_enqueued_jobs

```ruby
# test/integration/notification_test.rb
require "test_helper"

class NotificationTest < ActionDispatch::IntegrationTest
  test "sends notification email" do
    assert_emails 1 do
      perform_enqueued_jobs do
        NotificationMailer.daily_digest(users(:one)).deliver_later
      end
    end
  end
end
```

## Mailer Implementation

### Basic Mailer

```ruby
# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    @login_url = new_session_url

    mail(to: @user.email_address, subject: t(".subject"))
  end

  def password_reset(user, token)
    @user = user
    @token = token
    @reset_url = edit_password_url(token: token)
    @expires_in = "24 hours"

    mail(to: @user.email_address, subject: t(".subject"))
  end
end
```

### Mailer with Attachments

```ruby
class ReportMailer < ApplicationMailer
  def monthly_report(user, report)
    @user = user
    @report = report

    attachments["report-#{Date.current}.pdf"] = report.to_pdf

    mail(to: @user.email_address, subject: t(".subject"))
  end
end
```

### Bundled Notification Pattern

Send one email with multiple notifications instead of many emails:

```ruby
class NotificationMailer < ApplicationMailer
  def daily_digest(user)
    @user = user
    @notifications = user.notifications.unread.today

    return if @notifications.empty?

    mail(to: @user.email_address, subject: t(".subject", count: @notifications.count))
  end
end
```

## Email Templates

```erb
<%# app/views/user_mailer/welcome.html.erb %>
<h1><%= t(".greeting", name: @user.name) %></h1>
<p><%= t(".intro") %></p>
<p><%= link_to t(".login_button"), @login_url, class: "button" %></p>
```

```erb
<%# app/views/user_mailer/welcome.text.erb %>
<%= t(".greeting", name: @user.name) %>

<%= t(".intro") %>

<%= t(".login_prompt") %>: <%= @login_url %>
```

## Delivery Methods

```ruby
# Background delivery (preferred)
UserMailer.welcome(user).deliver_later

# With delay
UserMailer.welcome(user).deliver_later(wait: 5.minutes)

# Immediate (avoid in production)
UserMailer.welcome(user).deliver_now
```

## Previews

```ruby
# test/mailers/previews/user_mailer_preview.rb
class UserMailerPreview < ActionMailer::Preview
  def welcome
    user = User.first
    UserMailer.welcome(user)
  end

  def password_reset
    user = User.first
    UserMailer.password_reset(user, "preview-token-123")
  end
end
```

Access at: `http://localhost:3000/rails/mailers`

## I18n for Emails

```yaml
# config/locales/mailers/en.yml
en:
  user_mailer:
    welcome:
      subject: "Welcome to Our App!"
      greeting: "Hello %{name}!"
      intro: "Thanks for signing up."
      login_button: "Log In Now"
      login_prompt: "Log in here"
    password_reset:
      subject: "Reset Your Password"
```

### Localized Delivery

```ruby
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    I18n.with_locale(user.locale || I18n.default_locale) do
      mail(to: @user.email_address, subject: t(".subject"))
    end
  end
end
```

## Checklist

- [ ] Mailer test written first (RED)
- [ ] Mailer method created
- [ ] HTML template created
- [ ] Text template created
- [ ] Uses I18n for all text
- [ ] Preview created
- [ ] Uses `deliver_later` (not `deliver_now`)
- [ ] All tests GREEN
