# State-as-Records Patterns

## Philosophy

Instead of boolean columns (`closed: true`), create separate state record models that capture who, when, and why.

## When to Use State Records vs Booleans

### Use State Records When:
- You need to track WHO changed the state
- You need to track WHEN the state changed
- You need to track WHY (reason, notes)
- State changes are business-significant events
- You need an audit trail

### Booleans Are OK When:
- It's a technical flag (`email_verified`, `terms_accepted`)
- No audit trail needed
- Simple on/off with no metadata
- Performance-critical hot paths

## Pattern 1: Simple Toggle (Closure)

```ruby
# Migration
class CreateClosures < ActiveRecord::Migration[8.0]
  def change
    create_table :closures do |t|
      t.references :card, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.timestamps
    end
    add_index :closures, :card_id, unique: true
  end
end

# app/models/closure.rb
class Closure < ApplicationRecord
  belongs_to :card, touch: true
  belongs_to :user, optional: true
  validates :card, uniqueness: true
end

# app/models/concerns/closeable.rb
module Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :open, -> { where.missing(:closure) }
    scope :closed, -> { joins(:closure) }
  end

  def close(user: Current.user)
    create_closure!(user: user)
  end

  def reopen
    closure&.destroy!
  end

  def closed?
    closure.present?
  end

  def open?
    !closed?
  end

  def closed_at
    closure&.created_at
  end

  def closed_by
    closure&.user
  end
end

# app/models/card.rb
class Card < ApplicationRecord
  include Closeable
end
```

## Pattern 2: State with Reason (Approval)

```ruby
class CreateApprovals < ActiveRecord::Migration[8.0]
  def change
    create_table :approvals do |t|
      t.references :approvable, polymorphic: true, null: false
      t.references :user, null: false, foreign_key: true
      t.text :notes
      t.timestamps
    end
    add_index :approvals, [:approvable_type, :approvable_id], unique: true
  end
end

class Approval < ApplicationRecord
  belongs_to :approvable, polymorphic: true, touch: true
  belongs_to :user
  validates :approvable, uniqueness: { scope: :approvable_type }
end

module Approvable
  extend ActiveSupport::Concern

  included do
    has_one :approval, as: :approvable, dependent: :destroy

    scope :approved, -> { joins(:approval) }
    scope :pending_approval, -> { where.missing(:approval) }
  end

  def approve!(user:, notes: nil)
    create_approval!(user: user, notes: notes)
  end

  def unapprove!
    approval&.destroy!
  end

  def approved?
    approval.present?
  end

  def approved_by
    approval&.user
  end

  def approved_at
    approval&.created_at
  end
end
```

## Pattern 3: State with History (Publication)

When you need to track multiple state transitions over time:

```ruby
class CreatePublications < ActiveRecord::Migration[8.0]
  def change
    create_table :publications do |t|
      t.references :post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false
      t.text :description
      t.timestamps
    end
    add_index :publications, :post_id, unique: true
    add_index :publications, :key, unique: true
  end
end

class Publication < ApplicationRecord
  belongs_to :post, touch: true
  belongs_to :user

  before_validation :generate_key, on: :create

  private

  def generate_key
    self.key ||= SecureRandom.alphanumeric(12)
  end
end
```

## CRUD Routing for State Records

```ruby
# config/routes.rb
resources :cards do
  resource :closure, only: [:create, :destroy]
end

resources :posts do
  resource :publication, only: [:create, :destroy]
end

resources :documents do
  resource :approval, only: [:create, :destroy]
end
```

```ruby
# app/controllers/closures_controller.rb
class ClosuresController < ApplicationController
  before_action :set_card

  def create
    authorize @card, :close?
    @card.close(user: Current.user)
    redirect_to @card, notice: "Closed."
  end

  def destroy
    authorize @card, :reopen?
    @card.reopen
    redirect_to @card, notice: "Reopened."
  end

  private

  def set_card
    @card = Card.find(params[:card_id])
  end
end
```

## Testing State Records

```ruby
# test/models/concerns/closeable_test.rb
require "test_helper"

class CloseableTest < ActiveSupport::TestCase
  setup do
    @card = cards(:open_card)
    @user = users(:one)
  end

  test "#close creates a closure" do
    assert_difference "Closure.count", 1 do
      @card.close(user: @user)
    end
    assert @card.closed?
    assert_equal @user, @card.closed_by
  end

  test "#reopen destroys the closure" do
    @card.close(user: @user)
    @card.reopen
    assert @card.open?
  end

  test ".open scope excludes closed cards" do
    @card.close(user: @user)
    assert_not_includes Card.open, @card
  end

  test ".closed scope includes closed cards" do
    @card.close(user: @user)
    assert_includes Card.closed, @card
  end
end
```
