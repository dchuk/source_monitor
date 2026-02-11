---
name: i18n-patterns
description: Implements internationalization with Rails I18n for multi-language support. Use when adding translations, managing locales, localizing dates/currencies, pluralization, or when user mentions i18n, translations, locales, or multi-language.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# I18n Patterns for Rails 8

## Overview

Rails I18n provides internationalization support:
- Translation lookups
- Locale management
- Date/time/currency formatting
- Pluralization rules
- Lazy lookups in views

## Quick Start

```ruby
# config/application.rb
config.i18n.default_locale = :en
config.i18n.available_locales = [:en, :fr, :de]
config.i18n.fallbacks = true
```

## Project Structure

```
config/locales/
├── en.yml                    # English defaults
├── fr.yml                    # French defaults
├── models/
│   ├── en.yml               # Model translations
│   └── fr.yml
├── views/
│   ├── en.yml               # View translations
│   └── fr.yml
├── mailers/
│   ├── en.yml
│   └── fr.yml
└── components/
    ├── en.yml
    └── fr.yml
```

## Locale File Organization

### Models

```yaml
# config/locales/models/en.yml
en:
  activerecord:
    models:
      event: Event
    attributes:
      event:
        name: Name
        event_date: Event Date
        status: Status
      event/statuses:
        draft: Draft
        confirmed: Confirmed
        cancelled: Cancelled
    errors:
      models:
        event:
          attributes:
            name:
              blank: "can't be blank"
```

### Views

```yaml
# config/locales/views/en.yml
en:
  events:
    index:
      title: Events
      new_event: New Event
      no_events: No events found
    show:
      edit: Edit
      delete: Delete
      confirm_delete: Are you sure?
    create:
      success: Event was successfully created.
    destroy:
      success: Event was successfully deleted.
```

### Common/Shared

```yaml
# config/locales/en.yml
en:
  common:
    actions:
      save: Save
      cancel: Cancel
      delete: Delete
      edit: Edit
      back: Back
      search: Search
    messages:
      loading: Loading...
      no_results: No results found
      not_specified: Not specified
```

## Usage Patterns

### In Views (Lazy Lookup)

```erb
<%# t(".title") resolves to "events.index.title" %>
<h1><%= t(".title") %></h1>

<%# With interpolation %>
<p><%= t(".welcome", name: current_user.name) %></p>

<%# With HTML (use _html suffix) %>
<p><%= t(".intro_html", link: link_to("here", help_path)) %></p>
```

### In Controllers

```ruby
class EventsController < ApplicationController
  def create
    @event = current_account.events.build(event_params)
    if @event.save
      redirect_to @event, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

### In Models

```ruby
class Event < ApplicationRecord
  def status_text
    I18n.t("activerecord.attributes.event/statuses.#{status}")
  end
end
```

### In Presenters

```ruby
class EventPresenter < BasePresenter
  def formatted_date
    return not_specified if event_date.nil?
    I18n.l(event_date, format: :long)
  end

  private

  def not_specified
    tag.span(I18n.t("common.messages.not_specified"), class: "text-slate-400 italic")
  end
end
```

## Date/Time/Number Formatting

```ruby
I18n.l(Date.current)                    # "January 15, 2024"
I18n.l(Date.current, format: :short)    # "Jan 15"
I18n.l(Date.current, format: :long)     # "Wednesday, January 15, 2024"

number_to_currency(1234.50)             # "$1,234.50"
number_to_currency(1234.50, locale: :fr) # "1 234,50 EUR"
```

## Pluralization

```yaml
en:
  events:
    count:
      zero: No events
      one: 1 event
      other: "%{count} events"
```

```ruby
t("events.count", count: 0)   # "No events"
t("events.count", count: 1)   # "1 event"
t("events.count", count: 5)   # "5 events"
```

## Locale Switching

### URL-Based

```ruby
# config/routes.rb
scope "(:locale)", locale: /en|fr|de/ do
  resources :events
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  around_action :switch_locale

  private

  def switch_locale(&action)
    locale = params[:locale] || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
```

### User Preference

```ruby
def switch_locale(&action)
  locale = current_user&.locale || extract_locale_from_header || I18n.default_locale
  I18n.with_locale(locale, &action)
end
```

## Testing I18n

### Missing Translation Detection

```ruby
# test/i18n_test.rb
require "test_helper"

class I18nTest < ActiveSupport::TestCase
  test "no missing translations for English" do
    # Use i18n-tasks gem for comprehensive checks
    # Or manually verify critical paths
    assert I18n.t("events.index.title", locale: :en).present?
    assert I18n.t("events.create.success", locale: :en).present?
  end

  test "all available locales have required keys" do
    required_keys = %w[
      events.index.title
      events.create.success
      common.actions.save
      common.actions.cancel
    ]

    I18n.available_locales.each do |locale|
      required_keys.each do |key|
        translation = I18n.t(key, locale: locale, raise: true)
        assert translation.present?, "Missing #{locale}.#{key}"
      end
    end
  end
end
```

### View Translation Test

```ruby
# test/controllers/events_controller_test.rb
require "test_helper"

class EventsI18nTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "index page uses translations" do
    get events_path
    assert_response :success
    assert_includes response.body, I18n.t("events.index.title")
  end

  test "index page works in French" do
    get events_path(locale: :fr)
    assert_response :success
    assert_includes response.body, I18n.t("events.index.title", locale: :fr)
  end
end
```

## i18n-tasks Gem

```bash
bundle exec i18n-tasks missing     # Find missing translations
bundle exec i18n-tasks unused      # Find unused translations
bundle exec i18n-tasks normalize   # Normalize locale files
bundle exec i18n-tasks health      # Health check
```

## Best Practices

- Use lazy lookups in views: `t(".title")` not `t("events.index.title")`
- Use `_html` suffix for HTML content
- Use interpolation for dynamic content: `t(".greeting", name: name)`
- Organize locale files by domain (models, views, mailers)
- Never hardcode user-facing strings in views
- Never concatenate translations

## Checklist

- [ ] Locale files organized by domain
- [ ] All user-facing text uses I18n
- [ ] Lazy lookups in views
- [ ] Pluralization for countable items
- [ ] Date/currency formatting localized
- [ ] Locale switching implemented
- [ ] Missing translation detection in tests
- [ ] All tests GREEN
