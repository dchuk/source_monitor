---
name: rails-tdd
description: Guides Red-Green-Refactor TDD workflow using Minitest and fixtures. Use when the user wants to implement a feature using TDD, write tests first, follow test-driven practices, or mentions red-green-refactor, test-driven development, or writing tests before code.
tools: Read, Write, Edit, Bash, Glob, Grep
---

# TDD Workflow — Red-Green-Refactor

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

## The TDD Cycle

```
1. RED    → Write a failing test that describes desired behavior
2. GREEN  → Write the minimum code to make the test pass
3. REFACTOR → Improve code while keeping tests green
4. REPEAT → Next behavior
```

## Workflow Checklist

```
- [ ] Understand the requirement (input, output, edge cases)
- [ ] Choose test type (model/controller/system/service/etc.)
- [ ] Create or update fixtures as needed
- [ ] Write ONE failing test (RED)
- [ ] Run test — verify it FAILS with expected error
- [ ] Write minimum code to pass (GREEN)
- [ ] Run test — verify it PASSES
- [ ] Refactor if needed (improve code, keep tests green)
- [ ] Run ALL tests — verify nothing broke
- [ ] Repeat for the next behavior
```

## Choosing the Right Test Type

| What You're Building | Test Type | Base Class |
|---------------------|-----------|------------|
| Validation, scope, method | Model test | `ActiveSupport::TestCase` |
| HTTP endpoint | Controller test | `ActionDispatch::IntegrationTest` |
| Multi-model business logic | Service test | `ActiveSupport::TestCase` |
| Complex query | Query test | `ActiveSupport::TestCase` |
| Authorization rule | Policy test | `ActiveSupport::TestCase` |
| Reusable UI component | Component test | `ViewComponent::TestCase` |
| Background processing | Job test | `ActiveJob::TestCase` |
| Email content | Mailer test | `ActionMailer::TestCase` |
| Full user flow with JS | System test | `ApplicationSystemTestCase` |

## Writing Good Failing Tests (RED)

### One Concept Per Test

```ruby
# GOOD: One concept each
test "requires title" do
  post = Post.new(title: nil)
  assert_not post.valid?
  assert_includes post.errors[:title], "can't be blank"
end

test "requires body" do
  post = Post.new(body: nil)
  assert_not post.valid?
end

# BAD: Multiple concepts
test "validates presence" do
  post = Post.new(title: nil, body: nil)
  assert_not post.valid?
  assert_includes post.errors[:title], "can't be blank"
  assert_includes post.errors[:body], "can't be blank"
end
```

### Descriptive Test Names

```ruby
# GOOD: Names describe behavior
test "published scope returns only published posts"
test "returns failure when cart is empty"
test "admin can destroy any event"

# BAD: Vague
test "scope works"
test "handles error"
```

### Verify the Failure

Run the test. The failure should tell you what's missing:

```
# GOOD failures: NameError: uninitialized constant Post
#                NoMethodError: undefined method 'publish!'
# BAD failures:  ActiveRecord::ConnectionNotEstablished
#                SyntaxError: unexpected end
```

## Minimal Implementation (GREEN)

Write the MINIMUM code to pass — no optimization, no untested edge cases:

```ruby
# Test says: requires title
# GREEN: Just add the validation
validates :title, presence: true

# NOT this (over-engineering without tests):
validates :title, presence: true, length: { minimum: 3, maximum: 255 },
                  uniqueness: { scope: :account_id }
```

## Refactoring Rules

1. Only refactor when tests are GREEN
2. One change at a time
3. Run tests after EACH change
4. If tests break, undo the last change
5. Don't add new features during refactoring

## Example: TDD a Complete Model

**Requirement:** Event with name, date, upcoming scope, days_until method

```ruby
# Cycle 1: RED — test validation
test "requires name" do
  event = Event.new(name: nil)
  assert_not event.valid?
  assert_includes event.errors[:name], "can't be blank"
end
# GREEN: validates :name, presence: true

# Cycle 2: RED — test another validation
test "requires event_date" do
  event = Event.new(event_date: nil)
  assert_not event.valid?
end
# GREEN: validates :event_date, presence: true

# Cycle 3: RED — test scope
test ".upcoming returns only future events" do
  assert_includes Event.upcoming, events(:upcoming)
  assert_not_includes Event.upcoming, events(:past)
end
# GREEN: scope :upcoming, -> { where("event_date >= ?", Date.current) }

# Cycle 4: RED — test method
test "#days_until returns days until event" do
  event = Event.new(event_date: 5.days.from_now.to_date)
  assert_equal 5, event.days_until
end
# GREEN: def days_until = (event_date - Date.current).to_i
```

## Example: TDD a Controller Action

```ruby
# Cycle 1: Authentication required
test "create requires authentication" do
  post events_url, params: { event: { name: "Test" } }
  assert_redirected_to new_session_url
end

# Cycle 2: Successful create
test "creates event with valid params" do
  sign_in_as users(:regular)
  assert_difference("Event.count") do
    post events_url, params: {
      event: { name: "New Event", event_date: 1.week.from_now.to_date }
    }
  end
  assert_redirected_to event_url(Event.last)
end

# Cycle 3: Validation errors
test "renders errors for invalid params" do
  sign_in_as users(:regular)
  assert_no_difference("Event.count") do
    post events_url, params: { event: { name: "" } }
  end
  assert_response :unprocessable_entity
end
```

## Example: TDD a Service Object

```ruby
# Cycle 1: Success path
test "returns success with valid params" do
  result = @service.call(user: @user, items: [{ product_id: @product.id, quantity: 1 }])
  assert result.success?
  assert_kind_of Order, result.data
end
# GREEN: Minimal service that creates order and returns Result.success

# Cycle 2: Line items
test "creates line items" do
  assert_difference "LineItem.count", 1 do
    @service.call(user: @user, items: [{ product_id: @product.id, quantity: 2 }])
  end
end
# GREEN: Add line item creation to service

# Cycle 3: Failure path
test "returns failure with empty items" do
  result = @service.call(user: @user, items: [])
  assert result.failure?
  assert_equal :empty_cart, result.code
end
# GREEN: Add guard clause

# Cycle 4: Transaction safety
test "rolls back on error" do
  assert_no_difference "Order.count" do
    @service.call(user: @user, items: [{ product_id: 0, quantity: 1 }])
  end
end
# GREEN: Wrap in transaction
```

## TDD Order for a New Feature

Build from fastest to slowest, most isolated to most integrated:

1. **Model tests** — Validations, scopes, methods
2. **Policy tests** — Authorization rules
3. **Service tests** — Business logic (if needed)
4. **Controller tests** — HTTP integration
5. **Component tests** — UI components (if applicable)
6. **System tests** — 1-2 critical end-to-end flows

## Anti-Patterns to Avoid

### Testing Implementation, Not Behavior

```ruby
# BAD: Tests how it works
test "calls update! on the record" do
  assert_called(order, :update!) { order.fulfill! }
end

# GOOD: Tests what it does
test "sets fulfilled_at timestamp" do
  order.fulfill!
  assert_not_nil order.reload.fulfilled_at
end
```

### Mystery Guest

```ruby
# BAD: users(:one) — what state?
sign_in_as users(:one)

# GOOD: Descriptive fixture name
sign_in_as users(:regular)
```

### Over-Specifying

```ruby
# BAD: Brittle — breaks if wording changes
assert_equal "Your cart is empty. Please add items.", result.error

# GOOD: Tests concept
assert result.failure?
assert_equal :empty_cart, result.code
```

### Skipping the RED Step

Always see the test fail first. If it passes immediately, either the behavior already exists or the test isn't testing what you think.

### Too Many System Tests

```ruby
# BAD: System test for something a model test covers
test "title is required" do
  visit new_post_url
  click_button "Create Post"
  assert_text "can't be blank"
end

# GOOD: Model test for validations, system test only for critical flow
```

## Running Tests During TDD

```bash
bin/rails test test/models/event_test.rb       # Single file
bin/rails test test/models/event_test.rb:15    # Single test by line
bin/rails test test/models/                    # All model tests
bin/rails test                                 # Full suite before commit
bin/rails test --verbose                       # See test names
```

## TDD Session Checklist

- [ ] Understand the full requirement
- [ ] Identify all behaviors to test
- [ ] Create/update fixtures for test scenarios
- [ ] Plan test order (model -> policy -> service -> controller -> system)
- [ ] Start the RED-GREEN-REFACTOR cycle
- [ ] Run full test suite before declaring done
