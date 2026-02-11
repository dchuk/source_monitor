---
name: api-versioning
description: Implements RESTful API design with versioning and request tests. Use when building APIs, adding API endpoints, versioning APIs, or when user mentions REST, JSON API, or API design.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# API Versioning for Rails 8

## Overview

Well-structured APIs need versioning for backwards compatibility and clear organization.

**Recommended**: URL Path versioning (`/api/v1/users`)

## Quick Setup

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :show, :create, :update, :destroy]
      resources :events, only: [:index, :show, :create]
    end
  end
end
```

### Directory Structure

```
app/controllers/
├── api/
│   ├── base_controller.rb
│   ├── v1/
│   │   ├── base_controller.rb
│   │   ├── users_controller.rb
│   │   └── events_controller.rb
│   └── v2/
│       ├── base_controller.rb
│       └── users_controller.rb
```

### Base Controller

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def not_found(exception)
      render json: { error: exception.message }, status: :not_found
    end

    def unprocessable_entity(exception)
      render json: { errors: exception.record.errors }, status: :unprocessable_entity
    end

    def bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end
  end
end
```

### Version Base Controller

```ruby
# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < Api::BaseController
    end
  end
end
```

### Resource Controller

```ruby
# app/controllers/api/v1/users_controller.rb
module Api
  module V1
    class UsersController < BaseController
      before_action :set_user, only: [:show, :update, :destroy]

      def index
        @users = User.page(params[:page]).per(25)
        render json: { data: @users, meta: pagination_meta(@users) }
      end

      def show
        render json: { data: @user }
      end

      def create
        @user = User.create!(user_params)
        render json: { data: @user }, status: :created
      end

      def update
        @user.update!(user_params)
        render json: { data: @user }
      end

      def destroy
        @user.destroy
        head :no_content
      end

      private

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:name, :email)
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count
        }
      end
    end
  end
end
```

## API Authentication

### Bearer Token Auth

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ApplicationController
    before_action :authenticate_api_user!

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.split(" ")&.last
      @current_api_user = Session.find_by(token: token)&.user

      render json: { error: "Unauthorized" }, status: :unauthorized unless @current_api_user
    end

    def current_api_user
      @current_api_user
    end
  end
end
```

## Response Format

```json
// Success (single)
{ "data": { "id": 1, "name": "John", "email": "john@example.com" } }

// Success (collection)
{ "data": [...], "meta": { "current_page": 1, "total_pages": 10 } }

// Error
{ "error": "Record not found" }

// Validation errors
{ "errors": { "email": ["has already been taken"] } }
```

## Testing APIs (Minitest)

### Request Test Template

```ruby
# test/controllers/api/v1/users_controller_test.rb
require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = {
      "Accept" => "application/json",
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_token_for(@user)}"
    }
  end

  # -- index --
  test "GET /api/v1/users returns all users" do
    get "/api/v1/users", headers: @headers

    assert_response :success
    data = json_response["data"]
    assert_kind_of Array, data
  end

  # -- show --
  test "GET /api/v1/users/:id returns the user" do
    get "/api/v1/users/#{@user.id}", headers: @headers

    assert_response :success
    assert_equal @user.id, json_response["data"]["id"]
  end

  test "GET /api/v1/users/:id returns 404 for missing user" do
    get "/api/v1/users/999999", headers: @headers

    assert_response :not_found
    assert json_response["error"].present?
  end

  # -- create --
  test "POST /api/v1/users creates a user" do
    params = { user: { name: "New User", email: "new@example.com" } }

    assert_difference("User.count", 1) do
      post "/api/v1/users", params: params.to_json, headers: @headers
    end

    assert_response :created
  end

  test "POST /api/v1/users with invalid params returns errors" do
    params = { user: { name: "", email: "" } }

    assert_no_difference("User.count") do
      post "/api/v1/users", params: params.to_json, headers: @headers
    end

    assert_response :unprocessable_entity
    assert json_response["errors"].present?
  end

  # -- update --
  test "PATCH /api/v1/users/:id updates the user" do
    params = { user: { name: "Updated" } }

    patch "/api/v1/users/#{@user.id}", params: params.to_json, headers: @headers

    assert_response :success
    assert_equal "Updated", @user.reload.name
  end

  # -- destroy --
  test "DELETE /api/v1/users/:id destroys the user" do
    assert_difference("User.count", -1) do
      delete "/api/v1/users/#{@user.id}", headers: @headers
    end

    assert_response :no_content
  end

  # -- authentication --
  test "returns 401 without token" do
    get "/api/v1/users", headers: { "Accept" => "application/json" }

    assert_response :unauthorized
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def api_token_for(user)
    user.sessions.create!.token
  end
end
```

## Checklist

- [ ] Routes namespaced under `api/v1`
- [ ] Base controller with error handling
- [ ] Authentication configured
- [ ] Standard response format
- [ ] Request tests written
- [ ] 404/422/401 error cases tested
- [ ] All tests GREEN
