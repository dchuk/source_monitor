---
name: viewcomponent-patterns
description: Creates ViewComponents for reusable UI elements with TDD. Use when building reusable UI components, extracting complex partials, creating cards/tables/badges/modals, or when user mentions ViewComponent, components, or reusable UI.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# ViewComponent Patterns for Rails 8

## Overview

ViewComponents are Ruby objects for building reusable, testable view components:
- Faster than partials (no partial lookup)
- Unit testable without full request cycle
- Encapsulate view logic with Ruby
- Type-safe with explicit interfaces

## TDD Workflow

```
ViewComponent Progress:
- [ ] Step 1: Write component test (RED)
- [ ] Step 2: Run test (fails - no component)
- [ ] Step 3: Generate component skeleton
- [ ] Step 4: Implement component
- [ ] Step 5: Run test (GREEN)
- [ ] Step 6: Add variants/slots if needed
```

## Step 1: Component Test (RED)

```ruby
# test/components/card_component_test.rb
require "test_helper"

class CardComponentTest < ViewComponent::TestCase
  test "renders the title" do
    render_inline(CardComponent.new(title: "Test Title"))
    assert_selector "h3", text: "Test Title"
  end

  test "renders content block" do
    render_inline(CardComponent.new(title: "Title")) { "Card content" }
    assert_text "Card content"
  end

  test "renders subtitle when provided" do
    render_inline(CardComponent.new(title: "Title", subtitle: "Subtitle"))
    assert_selector "p", text: "Subtitle"
  end

  test "does not render subtitle element when not provided" do
    render_inline(CardComponent.new(title: "Title"))
    assert_no_selector ".subtitle"
  end
end
```

## Step 2-4: Implement Component

### Base Component

```ruby
# app/components/application_component.rb
class ApplicationComponent < ViewComponent::Base
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::NumberHelper

  def not_specified_span
    tag.span(I18n.t("components.common.not_specified"), class: "text-slate-400 italic")
  end
end
```

### Basic Component

```ruby
# app/components/card_component.rb
class CardComponent < ApplicationComponent
  def initialize(title:, subtitle: nil)
    @title = title
    @subtitle = subtitle
  end

  attr_reader :title, :subtitle

  def subtitle?
    subtitle.present?
  end
end
```

```erb
<%# app/components/card_component.html.erb %>
<div class="bg-white rounded-lg shadow p-6">
  <h3 class="text-lg font-semibold text-slate-900"><%= title %></h3>
  <% if subtitle? %>
    <p class="subtitle text-sm text-slate-500"><%= subtitle %></p>
  <% end %>
  <div class="mt-4">
    <%= content %>
  </div>
</div>
```

## Common Patterns

### Pattern 1: Status Badge

```ruby
# app/components/badge_component.rb
class BadgeComponent < ApplicationComponent
  VARIANTS = {
    success: "bg-green-100 text-green-800",
    warning: "bg-yellow-100 text-yellow-800",
    error: "bg-red-100 text-red-800",
    info: "bg-blue-100 text-blue-800",
    neutral: "bg-slate-100 text-slate-800"
  }.freeze

  def initialize(text:, variant: :neutral)
    @text = text
    @variant = variant.to_sym
  end

  def call
    tag.span(
      @text,
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{variant_classes}"
    )
  end

  private

  def variant_classes
    VARIANTS.fetch(@variant, VARIANTS[:neutral])
  end
end
```

Testing:

```ruby
# test/components/badge_component_test.rb
require "test_helper"

class BadgeComponentTest < ViewComponent::TestCase
  test "renders success variant" do
    render_inline(BadgeComponent.new(text: "Active", variant: :success))
    assert_selector ".bg-green-100"
    assert_text "Active"
  end

  test "renders error variant" do
    render_inline(BadgeComponent.new(text: "Failed", variant: :error))
    assert_selector ".bg-red-100"
  end

  test "defaults to neutral variant" do
    render_inline(BadgeComponent.new(text: "Unknown"))
    assert_selector ".bg-slate-100"
  end
end
```

### Pattern 2: Component with Slots

```ruby
# app/components/card_component.rb
class CardComponent < ApplicationComponent
  renders_one :header
  renders_one :footer
  renders_many :actions

  def initialize(title: nil)
    @title = title
  end
end
```

Testing slots:

```ruby
# test/components/card_component_test.rb
class CardComponentTest < ViewComponent::TestCase
  test "renders header slot" do
    render_inline(CardComponent.new) do |card|
      card.with_header { "Custom Header" }
    end

    assert_text "Custom Header"
  end

  test "renders multiple action slots" do
    render_inline(CardComponent.new) do |card|
      card.with_action { "Action 1" }
      card.with_action { "Action 2" }
    end

    assert_text "Action 1"
    assert_text "Action 2"
  end
end
```

### Pattern 3: Collection Component

```ruby
# app/components/event_card_component.rb
class EventCardComponent < ApplicationComponent
  with_collection_parameter :event

  def initialize(event:)
    @event = event
  end

  delegate :name, :event_date, :status, to: :@event

  def formatted_date
    return not_specified_span if event_date.nil?
    I18n.l(event_date, format: :long)
  end

  def status_badge
    render BadgeComponent.new(text: status.humanize, variant: status_variant)
  end

  private

  def status_variant
    case status.to_sym
    when :confirmed then :success
    when :cancelled then :error
    when :pending then :warning
    else :neutral
    end
  end
end
```

Testing collections:

```ruby
# test/components/event_card_component_test.rb
class EventCardComponentTest < ViewComponent::TestCase
  test "renders single event" do
    event = events(:one)
    render_inline(EventCardComponent.new(event: event))
    assert_text event.name
  end

  test "renders collection" do
    events_list = [events(:one), events(:two)]
    render_inline(EventCardComponent.with_collection(events_list))
    assert_selector ".event-card", count: 2
  end
end
```

### Pattern 4: Modal Component

```ruby
# app/components/modal_component.rb
class ModalComponent < ApplicationComponent
  renders_one :trigger
  renders_one :title
  renders_one :footer

  def initialize(id:, size: :medium)
    @id = id
    @size = size
  end

  def size_classes
    case @size
    when :small then "max-w-md"
    when :medium then "max-w-lg"
    when :large then "max-w-2xl"
    when :full then "max-w-full mx-4"
    end
  end
end
```

## Usage in Views

```erb
<%# Simple component %>
<%= render BadgeComponent.new(text: "Active", variant: :success) %>

<%# Component with block %>
<%= render CardComponent.new(title: "Stats") do %>
  <p>Content here</p>
<% end %>

<%# Component with slots %>
<%= render CardComponent.new do |card| %>
  <% card.with_header do %>
    <h2>Header</h2>
  <% end %>
  Content
<% end %>

<%# Collection %>
<%= render EventCardComponent.with_collection(@events) %>
```

## Previews (Development)

```ruby
# test/components/previews/badge_component_preview.rb
class BadgeComponentPreview < ViewComponent::Preview
  def success
    render BadgeComponent.new(text: "Active", variant: :success)
  end

  def error
    render BadgeComponent.new(text: "Failed", variant: :error)
  end
end
```

Access at: `http://localhost:3000/rails/view_components`

## Checklist

- [ ] Test written first (RED)
- [ ] Extends `ApplicationComponent`
- [ ] Uses slots for flexible content
- [ ] Variants use constants (Open/Closed)
- [ ] Tested with different inputs
- [ ] Collection rendering tested
- [ ] Preview created for development
- [ ] All tests GREEN
