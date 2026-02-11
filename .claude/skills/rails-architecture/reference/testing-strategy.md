# Testing Strategy by Layer

## Test Pyramid

```
        /\
       /  \  System Tests (few)
      /----\
     /      \  Controller/Integration Tests (moderate)
    /--------\
   /          \  Unit Tests (many)
  --------------
  Models, Services, Queries, Presenters, Components
```

## Unit Tests

### Model Tests

```ruby
# test/models/event_test.rb
require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "requires name" do
    event = Event.new(name: nil)
    assert_not event.valid?
    assert_includes event.errors[:name], "can't be blank"
  end

  test "requires event_date" do
    event = Event.new(event_date: nil)
    assert_not event.valid?
    assert_includes event.errors[:event_date], "can't be blank"
  end

  test ".upcoming returns only future events" do
    past_event = events(:past)
    future_event = events(:upcoming)

    results = Event.upcoming
    assert_includes results, future_event
    assert_not_includes results, past_event
  end

  test "#days_until returns days until event" do
    event = Event.new(event_date: 5.days.from_now.to_date)
    assert_equal 5, event.days_until
  end
end
```

### Service Tests

```ruby
# test/services/orders/create_service_test.rb
require "test_helper"

class Orders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @product = products(:widget)
    @service = Orders::CreateService.new
  end

  test "returns success with valid params" do
    result = @service.call(user: @user, items: [{ product_id: @product.id, quantity: 2 }])
    assert result.success?
    assert_kind_of Order, result.data
  end

  test "creates an order" do
    assert_difference "Order.count", 1 do
      @service.call(user: @user, items: [{ product_id: @product.id, quantity: 2 }])
    end
  end

  test "returns failure with empty items" do
    result = @service.call(user: @user, items: [])
    assert result.failure?
    assert_equal :empty_cart, result.code
  end

  test "does not create order on failure" do
    assert_no_difference "Order.count" do
      @service.call(user: @user, items: [])
    end
  end
end
```

### Query Tests

```ruby
# test/queries/active_events_query_test.rb
require "test_helper"

class ActiveEventsQueryTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @other_account = accounts(:two)
    @query = ActiveEventsQuery.new(account: @account)
  end

  test "returns active events for account" do
    active = events(:active)
    result = @query.call
    assert_includes result, active
  end

  test "excludes inactive events" do
    cancelled = events(:cancelled)
    result = @query.call
    assert_not_includes result, cancelled
  end

  test "excludes other account events (tenant isolation)" do
    other_event = events(:other_account_event)
    result = @query.call
    assert_not_includes result, other_event
  end
end
```

### Presenter Tests

```ruby
# test/presenters/event_presenter_test.rb
require "test_helper"

class EventPresenterTest < ActiveSupport::TestCase
  include ActionView::Helpers::TagHelper

  test "delegates to model" do
    event = events(:confirmed)
    presenter = EventPresenter.new(event)
    assert_equal event.name, presenter.name
  end

  test "#status_badge returns HTML-safe string" do
    presenter = EventPresenter.new(events(:confirmed))
    assert_predicate presenter.status_badge, :html_safe?
  end

  test "#status_badge includes status text" do
    presenter = EventPresenter.new(events(:confirmed))
    assert_match "Confirmed", presenter.status_badge
  end

  test "#formatted_date with date present" do
    event = events(:confirmed)
    presenter = EventPresenter.new(event)
    assert_match event.event_date.year.to_s, presenter.formatted_date
  end

  test "#formatted_date with nil date" do
    event = events(:no_date)
    presenter = EventPresenter.new(event)
    assert_match "TBD", presenter.formatted_date
  end
end
```

## Integration Tests

### Controller Tests

```ruby
# test/controllers/events_controller_test.rb
require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @event = events(:one)
    sign_in_as @user
  end

  test "should get index" do
    get events_url
    assert_response :success
  end

  test "shows only own account events" do
    get events_url
    assert_response :success
    other_event = events(:other_account_event)
    assert_no_match other_event.name, response.body
  end

  test "should create event" do
    assert_difference("Event.count") do
      post events_url, params: { event: { name: "New Event", event_date: 1.week.from_now } }
    end
    assert_redirected_to event_url(Event.last)
  end

  test "renders form with errors for invalid params" do
    post events_url, params: { event: { name: "" } }
    assert_response :unprocessable_entity
  end
end
```

### Policy Tests

```ruby
# test/policies/event_policy_test.rb
require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  test "owner can show" do
    user = users(:one)
    event = events(:one) # belongs to user's account
    assert EventPolicy.new(user, event).show?
  end

  test "non-owner cannot show" do
    user = users(:two) # different account
    event = events(:one)
    assert_not EventPolicy.new(user, event).show?
  end

  test "scope returns only own events" do
    user = users(:one)
    scope = EventPolicy::Scope.new(user, Event).resolve
    assert_includes scope, events(:one)
    assert_not_includes scope, events(:other_account_event)
  end
end
```

## System Tests

```ruby
# test/system/create_event_test.rb
require "application_system_test_case"

class CreateEventTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:one)
  end

  test "creates event successfully" do
    visit new_event_url

    fill_in "Name", with: "Company Party"
    fill_in "Event date", with: 1.month.from_now.to_date
    click_button "Create Event"

    assert_text "Event was successfully created"
    assert_text "Company Party"
  end

  test "shows validation errors" do
    visit new_event_url
    click_button "Create Event"
    assert_text "can't be blank"
  end
end
```

## Component Tests

```ruby
# test/components/event_card_component_test.rb
require "test_helper"

class EventCardComponentTest < ViewComponent::TestCase
  test "renders event name" do
    event = events(:one)
    render_inline(EventCardComponent.new(event: event))
    assert_text event.name
  end

  test "renders status badge" do
    render_inline(EventCardComponent.new(event: events(:confirmed)))
    assert_selector ".badge"
  end

  test "shows days until for upcoming events" do
    event = events(:upcoming)
    render_inline(EventCardComponent.new(event: event))
    assert_selector "[data-days-until]"
  end
end
```

## Test Helpers

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  fixtures :all

  def sign_in_as(user)
    post session_url, params: { email: user.email_address, password: "password" }
  end

  def sign_out
    delete session_url
  end
end
```

## Coverage Requirements

| Layer | Minimum Coverage |
|-------|-----------------|
| Models | 90% |
| Services | 95% |
| Queries | 90% |
| Controllers | 80% |
| Overall | 85% |

## Checklist

- [ ] Unit tests for all models (validations, scopes, methods)
- [ ] Service tests cover success/failure paths
- [ ] Query tests verify correctness and tenant isolation
- [ ] Controller tests for all endpoints
- [ ] Policy tests for authorization rules
- [ ] System tests for critical user flows
- [ ] Component tests for ViewComponents
- [ ] Fixtures with meaningful names
- [ ] Test helper with authentication methods
