---
name: rails-controller
description: Creates Rails controllers with TDD approach - integration test first, then implementation. Use when creating new controllers, adding controller actions, implementing CRUD operations, or when user mentions controllers, routes, or API endpoints.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Rails Controller Generator (TDD)

Creates RESTful controllers following project conventions with integration tests first.

## Quick Start

1. Write failing integration test in `test/controllers/` or `test/integration/`
2. Run test to confirm RED
3. Implement controller action
4. Run test to confirm GREEN
5. Refactor if needed

## Project Conventions

This project uses:
- **Pundit** for authorization (`authorize @resource`, `policy_scope(Model)`)
- **Pagy** for pagination
- **Presenters** for view formatting
- **Multi-tenancy** via `current_account`
- **Turbo Stream** responses for dynamic updates

## TDD Workflow

### Step 1: Create Integration Test (RED)

```ruby
# test/controllers/[resources]_controller_test.rb
require "test_helper"

class ResourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @resource = resources(:one)
    sign_in @user
  end

  # === INDEX ===
  test "GET /resources returns success" do
    get resources_path
    assert_response :success
  end

  test "GET /resources shows only current_account resources (multi-tenant)" do
    other_resource = resources(:other_account)

    get resources_path

    assert_includes response.body, @resource.name
    assert_not_includes response.body, other_resource.name
  end

  test "GET /resources paginates results" do
    get resources_path
    assert_response :success
  end

  # === SHOW ===
  test "GET /resources/:id returns success" do
    get resource_path(@resource)
    assert_response :success
  end

  test "GET /resources/:id returns 404 for other account" do
    other_resource = resources(:other_account)

    assert_raises(ActiveRecord::RecordNotFound) do
      get resource_path(other_resource)
    end
  end

  # === NEW ===
  test "GET /resources/new returns success" do
    get new_resource_path
    assert_response :success
  end

  # === CREATE ===
  test "POST /resources creates with valid params" do
    assert_difference("Resource.count", 1) do
      post resources_path, params: {
        resource: { name: "New Resource", field1: "value" }
      }
    end

    assert_redirected_to resources_path
    assert_equal @user.account, Resource.last.account
  end

  test "POST /resources rejects invalid params" do
    assert_no_difference("Resource.count") do
      post resources_path, params: {
        resource: { name: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  # === EDIT ===
  test "GET /resources/:id/edit returns success" do
    get edit_resource_path(@resource)
    assert_response :success
  end

  # === UPDATE ===
  test "PATCH /resources/:id updates with valid params" do
    patch resource_path(@resource), params: {
      resource: { name: "Updated Name" }
    }

    assert_redirected_to resource_path(@resource)
    assert_equal "Updated Name", @resource.reload.name
  end

  test "PATCH /resources/:id rejects invalid params" do
    patch resource_path(@resource), params: {
      resource: { name: "" }
    }

    assert_response :unprocessable_entity
  end

  # === DESTROY ===
  test "DELETE /resources/:id destroys resource" do
    assert_difference("Resource.count", -1) do
      delete resource_path(@resource)
    end

    assert_redirected_to resources_path
  end

  # === AUTHORIZATION ===
  test "unauthenticated user is redirected" do
    sign_out

    get resources_path
    assert_redirected_to new_session_path
  end
end
```

### Step 2: Run Test (Confirm RED)

```bash
bin/rails test test/controllers/resources_controller_test.rb
```

### Step 3: Implement Controller (GREEN)

```ruby
# app/controllers/[resources]_controller.rb
class ResourcesController < ApplicationController
  before_action :set_resource, only: [:show, :edit, :update, :destroy]

  def index
    authorize Resource, :index?
    @pagy, resources = pagy(policy_scope(Resource).order(created_at: :desc))
    @resources = resources.map { |r| ResourcePresenter.new(r) }
  end

  def show
    authorize @resource
    @resource = ResourcePresenter.new(@resource)
  end

  def new
    @resource = current_account.resources.build
    authorize @resource
  end

  def create
    @resource = current_account.resources.build(resource_params)
    authorize @resource

    if @resource.save
      redirect_to resources_path, notice: "Resource created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @resource
  end

  def update
    authorize @resource

    if @resource.update(resource_params)
      redirect_to @resource, notice: "Resource updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @resource
    @resource.destroy
    redirect_to resources_path, notice: "Resource deleted successfully"
  end

  private

  def set_resource
    @resource = policy_scope(Resource).find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:name, :field1, :field2)
  end
end
```

### Step 4: Run Test (Confirm GREEN)

```bash
bin/rails test test/controllers/resources_controller_test.rb
```

## Test Helpers

Add to `test/test_helper.rb`:

```ruby
class ActionDispatch::IntegrationTest
  def sign_in(user)
    session = user.identity.sessions.create!
    cookies.signed[:session_token] = session.token
  end

  def sign_out
    cookies.delete(:session_token)
  end
end
```

## Namespaced Controllers

For nested routes like `settings/accounts`:

```ruby
# app/controllers/settings/accounts_controller.rb
module Settings
  class AccountsController < ApplicationController
    before_action :set_account

    def show
      authorize @account
    end

    private

    def set_account
      @account = current_account
    end
  end
end
```

## Turbo Stream Response Pattern

```ruby
def create
  @resource = current_account.resources.build(resource_params)
  authorize @resource

  if @resource.save
    respond_to do |format|
      format.html { redirect_to resources_path, notice: "Created" }
      format.turbo_stream do
        flash.now[:notice] = "Created"
        @pagy, @resources = pagy(policy_scope(Resource).order(created_at: :desc))
        render turbo_stream: [
          turbo_stream.replace("resources-list", partial: "resources/list"),
          turbo_stream.update("modal", "")
        ]
      end
    end
  else
    render :new, status: :unprocessable_entity
  end
end
```

### Testing Turbo Streams

```ruby
test "POST /resources with turbo_stream format" do
  post resources_path, params: {
    resource: { name: "Turbo Resource" }
  }, as: :turbo_stream

  assert_response :success
  assert_includes response.body, "turbo-stream"
end
```

## Full CRUD Fixture Setup

```yaml
# test/fixtures/resources.yml
one:
  name: "My Resource"
  field1: "Value 1"
  account: one

two:
  name: "Another Resource"
  field1: "Value 2"
  account: one

other_account:
  name: "Other Account Resource"
  field1: "Value 3"
  account: two
```

## Checklist

- [ ] Integration test written first (RED)
- [ ] Multi-tenant isolation tested
- [ ] Authorization tested (redirect/404 for unauthorized)
- [ ] Controller uses `authorize` on every action
- [ ] Controller uses `policy_scope` for queries
- [ ] Presenter wraps models for views
- [ ] Strong parameters defined
- [ ] All 7 CRUD actions tested (index, show, new, create, edit, update, destroy)
- [ ] Invalid params tested (422 response)
- [ ] Turbo Stream responses tested (if applicable)
- [ ] All tests GREEN
