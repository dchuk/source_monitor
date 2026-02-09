---
name: rails-service-object
description: Creates service objects following single-responsibility principle with comprehensive tests. Use when extracting business logic from controllers, creating complex operations, implementing interactors, or when user mentions service objects or POROs.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Rails Service Object Pattern

## Overview

Service objects encapsulate business logic:
- Single responsibility (one public method: `#call`)
- Easy to test in isolation
- Reusable across controllers, jobs, rake tasks
- Clear input/output contract
- Dependency injection for testability

## When to Use Service Objects

| Scenario | Use Service Object? |
|----------|---------------------|
| Complex business logic spanning multiple models | Yes |
| Multiple model interactions in one operation | Yes |
| External API calls | Yes |
| Logic shared across controllers/jobs | Yes |
| Operations with side effects (emails, webhooks) | Yes |
| Simple CRUD operations | **No** (use model) |
| Single model validation | **No** (use model) |
| Simple query/filter | **No** (use scope or query object) |
| View formatting | **No** (use presenter) |
| Form handling with validations | **No** (use form object) |

## When NOT to Use Service Objects

**Don't create a service object when:**
- A model callback does the job (e.g., `after_create :send_welcome_email`)
- The logic is a single ActiveRecord operation
- A concern would share the behavior more naturally
- You're wrapping a single method call (adds indirection for no benefit)
- The "service" just delegates to one model method

**Rule of thumb:** If your service object's `#call` method is under 5 lines and calls one model method, you don't need it.

## Workflow Checklist

```
Service Object Progress:
- [ ] Step 1: Define input/output contract
- [ ] Step 2: Create service test (RED)
- [ ] Step 3: Run test (fails - no service)
- [ ] Step 4: Create service file with empty #call
- [ ] Step 5: Run test (fails - wrong return)
- [ ] Step 6: Implement #call method
- [ ] Step 7: Run test (GREEN)
- [ ] Step 8: Add error case tests
- [ ] Step 9: Implement error handling
- [ ] Step 10: Final test run
```

## Step 1: Define Contract

```markdown
## Service: Orders::CreateService

### Purpose
Creates a new order with inventory validation and payment processing.

### Input
- user: User (required)
- items: Array<Hash> (required) - [{product_id:, quantity:}]
- payment_method_id: Integer (optional)

### Output (Result object)
Success: { success?: true, data: Order }
Failure: { success?: false, error: String, code: Symbol }

### Dependencies
- inventory_service: Checks product availability
- payment_gateway: Processes payment

### Side Effects
- Creates Order and OrderItem records
- Decrements inventory
- Charges payment method
- Sends confirmation email (async)
```

## Step 2: Service Test

Location: `test/services/orders/create_service_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class Orders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @product = products(:available)
    @items = [{ product_id: @product.id, quantity: 2 }]
    @service = Orders::CreateService.new
  end

  test "#call with valid inputs returns success" do
    result = @service.call(user: @user, items: @items)

    assert result.success?
    assert_instance_of Order, result.data
    assert_equal @user, result.data.user
  end

  test "#call with valid inputs creates an order" do
    assert_difference("Order.count", 1) do
      @service.call(user: @user, items: @items)
    end
  end

  test "#call with empty items returns failure" do
    result = @service.call(user: @user, items: [])

    assert result.failure?
    assert_equal "No items provided", result.error
  end

  test "#call with insufficient inventory returns failure" do
    items = [{ product_id: @product.id, quantity: 999_999 }]

    result = @service.call(user: @user, items: items)

    assert result.failure?
  end

  test "#call with insufficient inventory does not create order" do
    items = [{ product_id: @product.id, quantity: 999_999 }]

    assert_no_difference("Order.count") do
      @service.call(user: @user, items: items)
    end
  end
end
```

## Step 3-6: Implement Service

Location: `app/services/orders/create_service.rb`

```ruby
# frozen_string_literal: true

module Orders
  class CreateService
    def initialize(inventory_service: InventoryService.new,
                   payment_gateway: PaymentGateway.new)
      @inventory_service = inventory_service
      @payment_gateway = payment_gateway
    end

    def call(user:, items:, payment_method_id: nil)
      return failure("No items provided", :empty_items) if items.empty?
      return failure("Insufficient inventory", :insufficient_inventory) unless inventory_available?(items)

      order = create_order(user, items)
      process_payment(order, payment_method_id) if payment_method_id

      success(order)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.message, :validation_failed)
    end

    private

    attr_reader :inventory_service, :payment_gateway

    def inventory_available?(items)
      items.all? do |item|
        inventory_service.available?(item[:product_id], item[:quantity])
      end
    end

    def create_order(user, items)
      ActiveRecord::Base.transaction do
        order = Order.create!(user: user, status: :pending)

        items.each do |item|
          order.order_items.create!(
            product_id: item[:product_id],
            quantity: item[:quantity]
          )
          inventory_service.decrement(item[:product_id], item[:quantity])
        end

        order
      end
    end

    def process_payment(order, payment_method_id)
      payment_gateway.charge(
        amount: order.total,
        payment_method_id: payment_method_id
      )
      order.update!(status: :paid)
    end

    def success(data)
      Result.new(success: true, data: data)
    end

    def failure(error, code = :unknown)
      Result.new(success: false, error: error, code: code)
    end
  end
end
```

## Result Object

```ruby
# app/services/result.rb
# frozen_string_literal: true

class Result
  attr_reader :data, :error, :code

  def initialize(success:, data: nil, error: nil, code: nil)
    @success = success
    @data = data
    @error = error
    @code = code
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def deconstruct_keys(keys)
    { success: @success, data: @data, error: @error, code: @code }
  end
end
```

## Testing with Mocked Dependencies

```ruby
class Orders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @inventory_service = Minitest::Mock.new
    @payment_gateway = Minitest::Mock.new
    @service = Orders::CreateService.new(
      inventory_service: @inventory_service,
      payment_gateway: @payment_gateway
    )
  end

  test "calls inventory service to check availability" do
    @inventory_service.expect(:available?, true, [Integer, Integer])
    @inventory_service.expect(:decrement, true, [Integer, Integer])

    @service.call(user: users(:one), items: [{ product_id: 1, quantity: 2 }])

    @inventory_service.verify
  end
end
```

## Calling Services

### From Controllers

```ruby
class OrdersController < ApplicationController
  def create
    result = Orders::CreateService.new.call(
      user: current_user,
      items: order_params[:items],
      payment_method_id: order_params[:payment_method_id]
    )

    if result.success?
      redirect_to result.data, notice: "Order created"
    else
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end
end
```

### From Jobs

```ruby
class ProcessOrderJob < ApplicationJob
  def perform(user_id, items)
    user = User.find(user_id)
    result = Orders::CreateService.new.call(user: user, items: items)

    unless result.success?
      Rails.logger.error("Order failed: #{result.error}")
    end
  end
end
```

## Directory Structure

```
app/services/
  result.rb
  orders/
    create_service.rb
    cancel_service.rb
  users/
    register_service.rb
  payments/
    charge_service.rb
```

## Conventions

1. **Naming**: `Namespace::VerbNounService` (e.g., `Orders::CreateService`)
2. **Location**: `app/services/[namespace]/[name]_service.rb`
3. **Interface**: Single public method `#call`
4. **Return**: Always return Result object
5. **Dependencies**: Inject via constructor
6. **Errors**: Catch and wrap in Result, don't raise

## Anti-Patterns to Avoid

1. **God service**: Too many responsibilities - split it
2. **Hidden dependencies**: Using globals instead of injection
3. **No return contract**: Returning different types
4. **Raising exceptions**: Use Result objects instead
5. **Service wrapping one method**: Just call the method directly
6. **Service with multiple public methods**: Use separate services

## Checklist

- [ ] Contract defined (input/output/side effects)
- [ ] Test written first (RED)
- [ ] Single public method `#call`
- [ ] Returns Result object consistently
- [ ] Dependencies injected via constructor
- [ ] Error cases tested
- [ ] Transaction wraps multi-model operations
- [ ] All tests GREEN
