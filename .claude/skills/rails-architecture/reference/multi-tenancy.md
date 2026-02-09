# Multi-Tenancy Patterns

## URL-Based Multi-Tenancy

The preferred pattern for Rails multi-tenancy: account ID in the URL path.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  scope "/:account_id" do
    resources :boards do
      resources :cards
    end
  end
end
# Routes: /accounts/123/boards/456/cards/789
```

## Current Attributes for Context

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account

  def user=(user)
    super
    self.account = user&.account
  end
end
```

## Controller Scoping

```ruby
class ApplicationController < ActionController::Base
  before_action :set_current_account

  private

  def set_current_account
    Current.account = current_user.accounts.find(params[:account_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Account not found"
  end
end

class BoardsController < ApplicationController
  def index
    @boards = Current.account.boards
  end

  def show
    @board = Current.account.boards.find(params[:id])
  end
end
```

## Account Model

```ruby
class Account < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  # All account resources
  has_many :boards, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :name, presence: true

  def member?(user)
    users.exists?(user.id)
  end

  def add_member(user, role: :member)
    memberships.find_or_create_by!(user: user) do |m|
      m.role = role
    end
  end
end
```

## Membership Model

```ruby
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :account

  enum :role, { member: 0, admin: 1, owner: 2 }

  validates :user_id, uniqueness: { scope: :account_id }
end
```

## Every Table Gets account_id

```ruby
class CreateBoards < ActiveRecord::Migration[8.0]
  def change
    create_table :boards do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    add_index :boards, [:account_id, :name], unique: true
  end
end
```

## Scoping Pattern (Explicit, Not Default Scope)

```ruby
# GOOD: Explicit scoping through association
Current.account.boards.find(params[:id])

# BAD: Default scope (implicit, hard to debug)
class Board < ApplicationRecord
  default_scope { where(account_id: Current.account&.id) }
end
```

## Testing Multi-Tenancy

```ruby
# test/models/board_test.rb
require "test_helper"

class BoardTest < ActiveSupport::TestCase
  test "boards are scoped to account" do
    account = accounts(:one)
    other_account = accounts(:two)
    board = boards(:one) # belongs to accounts(:one)

    assert_includes account.boards, board
    assert_not_includes other_account.boards, board
  end
end

# test/controllers/boards_controller_test.rb
class BoardsControllerTest < ActionDispatch::IntegrationTest
  test "cannot access other account's boards" do
    sign_in_as users(:one) # belongs to accounts(:one)
    board = boards(:other_account_board) # belongs to accounts(:two)

    get board_url(board, account_id: accounts(:two).id)
    assert_redirected_to root_path
  end
end
```
