---
name: authorization-pundit
description: Implements policy-based authorization with Pundit for resource access control. Use when adding authorization rules, checking permissions, restricting actions, role-based access, or when user mentions Pundit, policies, authorization, or permissions.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Authorization with Pundit for Rails 8

## Overview

Pundit provides policy-based authorization:
- Plain Ruby policy objects
- Convention over configuration
- Easy to test with Minitest
- Scoped queries for collections
- Works with any authentication system

## Quick Start

```bash
bundle add pundit
bin/rails generate pundit:install
bin/rails generate pundit:policy Event
```

## TDD Workflow

```
Authorization Progress:
- [ ] Step 1: Write policy test (RED)
- [ ] Step 2: Run test (fails)
- [ ] Step 3: Implement policy
- [ ] Step 4: Run test (GREEN)
- [ ] Step 5: Add policy to controller
- [ ] Step 6: Test integration
```

## Base Policy

```ruby
# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "Define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
```

## Policy Testing (Minitest)

### Basic Policy Test

```ruby
# test/policies/event_policy_test.rb
require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @user = users(:one) # belongs to @account
    @other_user = users(:other_account) # different account
    @event = events(:one) # belongs to @account
  end

  # -- index --
  test "index? permits any authenticated user" do
    policy = EventPolicy.new(@user, Event)
    assert policy.index?
  end

  # -- show --
  test "show? permits user from same account" do
    policy = EventPolicy.new(@user, @event)
    assert policy.show?
  end

  test "show? denies user from different account" do
    policy = EventPolicy.new(@other_user, @event)
    assert_not policy.show?
  end

  # -- create --
  test "create? permits user from same account" do
    new_event = Event.new(account: @account)
    policy = EventPolicy.new(@user, new_event)
    assert policy.create?
  end

  # -- update --
  test "update? permits user from same account" do
    policy = EventPolicy.new(@user, @event)
    assert policy.update?
  end

  test "update? denies user from different account" do
    policy = EventPolicy.new(@other_user, @event)
    assert_not policy.update?
  end

  # -- destroy --
  test "destroy? permits user from same account" do
    policy = EventPolicy.new(@user, @event)
    assert policy.destroy?
  end

  test "destroy? denies user from different account" do
    policy = EventPolicy.new(@other_user, @event)
    assert_not policy.destroy?
  end

  # -- Scope --
  test "Scope returns events for user account only" do
    scope = EventPolicy::Scope.new(@user, Event).resolve

    scope.each do |event|
      assert_equal @user.account_id, event.account_id
    end
  end

  test "Scope excludes other account events" do
    other_event = events(:other_account)
    scope = EventPolicy::Scope.new(@user, Event).resolve

    assert_not_includes scope, other_event
  end
end
```

### Role-Based Policy Test

```ruby
# test/policies/event_policy_test.rb (role-based extension)
class EventPolicyRoleTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)
    @member = users(:one)
    @event = events(:one)
  end

  test "destroy? permits admin" do
    policy = EventPolicy.new(@admin, @event)
    assert policy.destroy?
  end

  test "publish? permits owner for draft events" do
    @event.update(status: :draft)
    policy = EventPolicy.new(@member, @event)
    assert policy.publish?
  end

  test "publish? denies for non-draft events" do
    @event.update(status: :published)
    policy = EventPolicy.new(@member, @event)
    assert_not policy.publish?
  end
end
```

## Policy Implementation

### Basic Policy (Account-Scoped)

```ruby
# app/policies/event_policy.rb
class EventPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    owner?
  end

  def create?
    true
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  private

  def owner?
    record.account_id == user.account_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: user.account_id)
    end
  end
end
```

### Role-Based Policy

```ruby
# app/policies/event_policy.rb
class EventPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    owner? || admin?
  end

  def create?
    member_or_above?
  end

  def update?
    owner_or_admin?
  end

  def destroy?
    admin?
  end

  def publish?
    owner_or_admin? && record.draft?
  end

  private

  def owner?
    record.account_id == user.account_id
  end

  def admin?
    user.admin?
  end

  def member_or_above?
    user.member? || user.admin?
  end

  def owner_or_admin?
    owner? || admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(account_id: user.account_id)
      end
    end
  end
end
```

## Controller Integration

```ruby
# app/controllers/events_controller.rb
class EventsController < ApplicationController
  def index
    @events = policy_scope(Event)
  end

  def show
    @event = Event.find(params[:id])
    authorize @event
  end

  def create
    @event = current_account.events.build(event_params)
    authorize @event

    if @event.save
      redirect_to @event, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @event = Event.find(params[:id])
    authorize @event
    @event.destroy
    redirect_to events_path, notice: t(".success")
  end
end
```

### Ensuring Authorization

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = t("pundit.not_authorized")
    redirect_back(fallback_location: root_path)
  end
end
```

## Testing Controller Authorization

```ruby
# test/controllers/events_controller_test.rb
require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:other_account)
    @event = events(:one) # belongs to @user's account
    @other_event = events(:other_account)
    sign_in @user
  end

  test "allows access to own events" do
    get event_path(@event)
    assert_response :success
  end

  test "denies access to other account events" do
    get event_path(@other_event)
    assert_redirected_to root_path
  end

  test "allows deletion of own events" do
    assert_difference("Event.count", -1) do
      delete event_path(@event)
    end
    assert_redirected_to events_path
  end

  test "denies deletion of other account events" do
    assert_no_difference("Event.count") do
      delete event_path(@other_event)
    end
    assert_redirected_to root_path
  end
end
```

## View Integration

```erb
<%# app/views/events/show.html.erb %>
<h1><%= @event.name %></h1>

<% if policy(@event).edit? %>
  <%= link_to t("common.edit"), edit_event_path(@event) %>
<% end %>

<% if policy(@event).destroy? %>
  <%= button_to t("common.delete"), @event, method: :delete,
                data: { confirm: t("common.confirm_delete") } %>
<% end %>
```

## Headless Policies

For actions not tied to a specific record:

```ruby
# app/policies/dashboard_policy.rb
class DashboardPolicy < ApplicationPolicy
  def initialize(user, _record = nil)
    @user = user
  end

  def show?
    true
  end

  def admin_panel?
    user.admin?
  end
end
```

```ruby
# Controller
authorize :dashboard, :admin_panel?
```

## Error Messages

```yaml
# config/locales/en.yml
en:
  pundit:
    not_authorized: You are not authorized to perform this action.
```

## Checklist

- [ ] Policy test written first (RED)
- [ ] Policy inherits from ApplicationPolicy
- [ ] Scope defined for collections
- [ ] Controller uses `authorize` and `policy_scope`
- [ ] `verify_authorized` after_action enabled
- [ ] Views use `policy(@record).action?`
- [ ] Error handling configured
- [ ] Multi-tenancy enforced in Scope
- [ ] All tests GREEN
