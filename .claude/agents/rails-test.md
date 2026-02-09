---
name: rails-test
description: Generates comprehensive Minitest tests with fixtures for all layers. Use when writing tests, creating test files, adding test coverage, debugging test failures, or when the user mentions testing, minitest, fixtures, test helpers, or test organization.
tools: Read, Write, Edit, Bash, Glob, Grep
---

# Comprehensive Minitest Testing

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

## Test Directory Structure

```
test/
├── test_helper.rb
├── application_system_test_case.rb
├── components/          # ViewComponent tests
├── controllers/         # Integration tests
├── fixtures/            # Test data (YAML)
├── jobs/                # ActiveJob tests
├── mailers/             # ActionMailer tests
│   └── previews/        # Mailer previews
├── models/              # Unit tests
│   └── concerns/        # Concern tests
├── policies/            # Pundit policy tests
├── presenters/          # Presenter tests
├── queries/             # Query object tests
├── services/            # Service object tests
└── system/              # Browser tests (Capybara)
```

## Test Helper Setup

```ruby
# test/test_helper.rb
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    fixtures :all
    parallelize(workers: :number_of_processors)

    def sign_in_as(user)
      post session_url, params: { email_address: user.email_address, password: "password" }
    end

    def sign_out
      delete session_url
    end

    def assert_success(result)
      assert result.success?, "Expected success but got failure: #{result.error}"
    end

    def assert_failure(result, code: nil)
      assert result.failure?, "Expected failure but got success"
      assert_equal code, result.code if code
    end
  end
end
```

```ruby
# test/application_system_test_case.rb
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]

  def sign_in_as(user)
    visit new_session_url
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_button "Sign in"
  end
end
```

## Fixture Best Practices

Name fixtures after their state. Use ERB sparingly. Reference other fixtures by label.

```yaml
# test/fixtures/users.yml
admin:
  name: Admin User
  email_address: admin@example.com
  password_digest: <%= BCrypt::Password.create("password") %>
  role: admin

regular:
  name: Regular User
  email_address: user@example.com
  password_digest: <%= BCrypt::Password.create("password") %>
  account: one

# test/fixtures/events.yml
upcoming:
  name: Upcoming Conference
  event_date: <%= 2.weeks.from_now.to_date %>
  account: one

past:
  name: Past Workshop
  event_date: <%= 1.month.ago.to_date %>
  account: one

other_account_event:
  name: Other Event
  event_date: <%= 1.week.from_now.to_date %>
  account: two
```

## Model Tests

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
    assert_includes Event.upcoming, events(:upcoming)
    assert_not_includes Event.upcoming, events(:past)
  end

  test "#days_until returns days until event" do
    event = Event.new(event_date: 5.days.from_now.to_date)
    assert_equal 5, event.days_until
  end
end
```

## Controller / Integration Tests

```ruby
# test/controllers/events_controller_test.rb
require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:regular)
    @event = events(:upcoming)
    sign_in_as @user
  end

  test "requires authentication" do
    sign_out
    get events_url
    assert_redirected_to new_session_url
  end

  test "should get index" do
    get events_url
    assert_response :success
  end

  test "index only shows own account events" do
    get events_url
    assert_no_match events(:other_account_event).name, response.body
  end

  test "should create event" do
    assert_difference("Event.count") do
      post events_url, params: {
        event: { name: "New Event", event_date: 1.week.from_now.to_date }
      }
    end
    assert_redirected_to event_url(Event.last)
  end

  test "renders errors for invalid event" do
    post events_url, params: { event: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "should update event" do
    patch event_url(@event), params: { event: { name: "Updated" } }
    assert_redirected_to event_url(@event)
    assert_equal "Updated", @event.reload.name
  end

  test "should destroy event" do
    assert_difference("Event.count", -1) do
      delete event_url(@event)
    end
    assert_redirected_to events_url
  end
end
```

## System Tests

```ruby
# test/system/events_test.rb
require "application_system_test_case"

class EventsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:regular)
  end

  test "creating an event" do
    visit new_event_url
    fill_in "Name", with: "Team Offsite"
    fill_in "Event date", with: 1.month.from_now.to_date
    click_button "Create Event"

    assert_text "Event was successfully created"
    assert_text "Team Offsite"
  end

  test "shows validation errors" do
    visit new_event_url
    click_button "Create Event"
    assert_text "can't be blank"
  end
end
```

## Service Tests

```ruby
# test/services/orders/create_service_test.rb
require "test_helper"

class Orders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular)
    @product = products(:widget)
    @service = Orders::CreateService.new
  end

  test "returns success with valid params" do
    result = @service.call(user: @user, items: [{ product_id: @product.id, quantity: 2 }])
    assert result.success?
    assert_kind_of Order, result.data
  end

  test "creates order and line items" do
    assert_difference ["Order.count", "LineItem.count"], 1 do
      @service.call(user: @user, items: [{ product_id: @product.id, quantity: 1 }])
    end
  end

  test "returns failure with empty items" do
    result = @service.call(user: @user, items: [])
    assert result.failure?
    assert_equal :empty_cart, result.code
  end

  test "rolls back transaction on error" do
    assert_no_difference "Order.count" do
      @service.call(user: @user, items: [{ product_id: 0, quantity: 1 }])
    end
  end
end
```

## Query, Presenter, and Component Tests

```ruby
# test/queries/active_events_query_test.rb
require "test_helper"

class ActiveEventsQueryTest < ActiveSupport::TestCase
  setup do
    @query = ActiveEventsQuery.new(account: accounts(:one))
  end

  test "returns active events for account" do
    assert_includes @query.call, events(:upcoming)
  end

  test "excludes other account events" do
    assert_not_includes @query.call, events(:other_account_event)
  end
end

# test/presenters/event_presenter_test.rb
require "test_helper"

class EventPresenterTest < ActiveSupport::TestCase
  test "#status_badge returns HTML-safe string" do
    presenter = EventPresenter.new(events(:upcoming))
    assert_predicate presenter.status_badge, :html_safe?
  end

  test "#formatted_date with nil date returns TBD" do
    presenter = EventPresenter.new(Event.new(event_date: nil))
    assert_match "TBD", presenter.formatted_date
  end
end

# test/components/event_card_component_test.rb
require "test_helper"

class EventCardComponentTest < ViewComponent::TestCase
  test "renders event name" do
    event = events(:upcoming)
    render_inline(EventCardComponent.new(event: event))
    assert_text event.name
  end

  test "renders status badge" do
    render_inline(EventCardComponent.new(event: events(:upcoming)))
    assert_selector ".badge"
  end
end
```

## Policy Tests

```ruby
# test/policies/event_policy_test.rb
require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = users(:regular)
    @other = users(:other_account)
    @event = events(:upcoming)
  end

  test "owner can show" do
    assert EventPolicy.new(@owner, @event).show?
  end

  test "non-owner cannot show" do
    assert_not EventPolicy.new(@other, @event).show?
  end

  test "scope returns only own account events" do
    scope = EventPolicy::Scope.new(@owner, Event).resolve
    assert_includes scope, @event
    assert_not_includes scope, events(:other_account_event)
  end
end
```

## Job and Mailer Tests

```ruby
# test/jobs/fulfill_order_job_test.rb
require "test_helper"

class FulfillOrderJobTest < ActiveJob::TestCase
  test "fulfills the order" do
    order = orders(:pending)
    FulfillOrderJob.perform_now(order.id)
    assert_not_nil order.reload.fulfilled_at
  end
end

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
```

## Performance Tips

| Test Type | Speed | Write First? |
|-----------|-------|--------------|
| Model / Service / Query / Policy | Fast | Yes |
| Component / Controller | Medium | For key features |
| System | Slow | Critical paths only |

- Prefer model/service tests over system tests (10-100x faster)
- Use `parallelize(workers: :number_of_processors)` for multi-core
- Use `assert_no_difference` instead of checking count before/after
- Avoid `sleep` in tests; use Capybara's built-in waiting

## Running Tests

```bash
bin/rails test                            # All tests
bin/rails test test/models/event_test.rb  # Single file
bin/rails test test/models/event_test.rb:15  # Single test by line
bin/rails test -n "test_requires_name"    # By name
bin/rails test --verbose                  # Verbose output
bin/rails test:system                     # System tests only
```

## Test Generation Checklist

- [ ] Model tests: validations, scopes, associations, methods
- [ ] Service tests: success path, failure path, edge cases
- [ ] Controller tests: auth, CRUD actions, error responses
- [ ] Policy tests: all actions, scope filtering
- [ ] Fixtures with meaningful names and minimal data
- [ ] System tests for 1-2 critical user paths
- [ ] Component tests if ViewComponents used
- [ ] Job tests for background processing
- [ ] Mailer tests for email content

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Using FactoryBot / RSpec | Not our convention | Use Minitest + fixtures |
| Testing implementation | Brittle, breaks on refactor | Test behavior and outcomes |
| Mystery guest | Unclear fixture references | Use descriptive fixture names |
| Too many system tests | Slow test suite | Prefer unit tests |
| No assertions | Test passes but verifies nothing | Every test needs an assertion |
| Hardcoded IDs | Breaks when fixtures change | Reference fixtures by name |
