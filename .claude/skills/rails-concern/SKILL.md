---
name: rails-concern
description: Creates Rails concerns for shared behavior across models or controllers with TDD. Use when extracting shared code, creating reusable modules, DRYing up models/controllers, or when user mentions concerns, modules, mixins, or shared behavior.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Rails Concern Generator (TDD)

Creates concerns (ActiveSupport::Concern modules) for shared behavior with tests first.

## Quick Start

1. Write failing test for the concern behavior
2. Run test to confirm RED
3. Implement concern in `app/models/concerns/` or `app/controllers/concerns/`
4. Run test to confirm GREEN

## When to Use Concerns

**Good use cases:**
- Shared validations across multiple models
- Common scopes used by several models
- Shared callbacks (e.g., UUID generation, slug creation)
- Controller authentication/authorization helpers
- Pagination or filtering logic
- Auditing and tracking behavior

**Avoid concerns when:**
- Logic is only used in one place (YAGNI)
- Creating "god" concerns with unrelated methods
- Logic should be a service object instead
- Concern would need its own state/config (use a class)

## TDD Workflow

### Step 1: Create Concern Test (RED)

For **Model Concerns**, test via a model that includes it:

```ruby
# test/models/concerns/has_uuid_test.rb
require "test_helper"

class HasUuidTest < ActiveSupport::TestCase
  test "generates uuid before validation on create" do
    event = Event.new(name: "Test", account: accounts(:one))
    event.valid?
    assert_present event.uuid
  end

  test "does not overwrite existing uuid" do
    event = Event.new(name: "Test", uuid: "custom-uuid", account: accounts(:one))
    event.valid?
    assert_equal "custom-uuid", event.uuid
  end

  test "validates uuid uniqueness" do
    existing = events(:one)
    event = Event.new(uuid: existing.uuid)
    assert_not event.valid?
    assert_includes event.errors[:uuid], "has already been taken"
  end

  test "find_by_uuid! finds record" do
    event = events(:one)
    assert_equal event, Event.find_by_uuid!(event.uuid)
  end

  test "find_by_uuid! raises for missing uuid" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Event.find_by_uuid!("nonexistent")
    end
  end
end
```

Alternative: Use a shared test module for concerns used by many models:

```ruby
# test/support/shared_tests/has_uuid_tests.rb
module HasUuidTests
  extend ActiveSupport::Concern

  included do
    test "generates uuid on create" do
      record = build_record_for_concern
      record.valid?
      assert_present record.uuid
    end
  end
end

# test/models/event_test.rb
class EventTest < ActiveSupport::TestCase
  include HasUuidTests

  private

  def build_record_for_concern
    Event.new(name: "Test", account: accounts(:one))
  end
end
```

For **Controller Concerns**, test via integration tests:

```ruby
# test/controllers/concerns/filterable_test.rb
require "test_helper"

class FilterableTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "filters resources by status" do
    get resources_path(status: "active")
    assert_response :success
    assert_includes response.body, resources(:active).name
    assert_not_includes response.body, resources(:inactive).name
  end
end
```

### Step 2: Run Test (Confirm RED)

```bash
bin/rails test test/models/concerns/has_uuid_test.rb
```

### Step 3: Implement Concern (GREEN)

**Model Concern:**

```ruby
# app/models/concerns/has_uuid.rb
module HasUuid
  extend ActiveSupport::Concern

  included do
    before_validation :generate_uuid, on: :create
    validates :uuid, presence: true, uniqueness: true
  end

  class_methods do
    def find_by_uuid!(uuid)
      find_by!(uuid: uuid)
    end
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

**Controller Concern:**

```ruby
# app/controllers/concerns/filterable.rb
module Filterable
  extend ActiveSupport::Concern

  private

  def apply_filters(scope, allowed_filters)
    allowed_filters.each do |filter|
      if params[filter].present?
        scope = scope.where(filter => params[filter])
      end
    end
    scope
  end
end
```

### Step 4: Run Test (Confirm GREEN)

```bash
bin/rails test test/models/concerns/has_uuid_test.rb
```

## Common Concern Patterns

### Pattern 1: UUID Generation

```ruby
# app/models/concerns/has_uuid.rb
module HasUuid
  extend ActiveSupport::Concern

  included do
    before_validation :generate_uuid, on: :create
    validates :uuid, presence: true, uniqueness: true
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

### Pattern 2: Soft Delete

```ruby
# app/models/concerns/soft_deletable.rb
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(deleted_at: nil) }
    scope :discarded, -> { where.not(deleted_at: nil) }
  end

  def discard
    update(deleted_at: Time.current)
  end

  def undiscard
    update(deleted_at: nil)
  end

  def discarded?
    deleted_at.present?
  end
end
```

### Pattern 3: Searchable

```ruby
# app/models/concerns/searchable.rb
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def search(query)
      return all if query.blank?

      columns = searchable_columns.map { |c| "#{table_name}.#{c}" }
      conditions = columns.map { |c| "#{c} LIKE :q" }.join(" OR ")
      where(conditions, q: "%#{sanitize_sql_like(query)}%")
    end

    def searchable_columns
      %w[name]
    end
  end
end
```

### Pattern 4: Auditable

```ruby
# app/models/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern

  included do
    has_many :audit_logs, as: :auditable, dependent: :destroy
    after_create :log_creation
    after_update :log_update
  end

  private

  def log_creation
    audit_logs.create(action: "created", changes_data: attributes)
  end

  def log_update
    return unless saved_changes.any?
    audit_logs.create(action: "updated", changes_data: saved_changes)
  end
end
```

### Pattern 5: Sluggable

```ruby
# app/models/concerns/sluggable.rb
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug, on: :create
    validates :slug, presence: true, uniqueness: { scope: slug_scope }
  end

  class_methods do
    def slug_scope
      nil
    end

    def find_by_slug!(slug)
      find_by!(slug: slug)
    end
  end

  def to_param
    slug
  end

  private

  def generate_slug
    return if slug.present?
    base_slug = slug_source.parameterize
    self.slug = base_slug
    counter = 1
    while self.class.exists?(slug: self.slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def slug_source
    respond_to?(:name) ? name : to_s
  end
end
```

### Pattern 6: Accountable (Multi-Tenancy)

```ruby
# app/models/concerns/accountable.rb
module Accountable
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    validates :account, presence: true

    scope :for_account, ->(account) { where(account: account) }
  end
end
```

### Pattern 7: Tokenizable

```ruby
# app/models/concerns/tokenizable.rb
module Tokenizable
  extend ActiveSupport::Concern

  included do
    has_secure_token :api_token
  end

  class_methods do
    def find_by_api_token!(token)
      find_by!(api_token: token)
    end
  end

  def regenerate_api_token!
    regenerate_api_token
    save!
  end
end
```

## Usage

**In Models:**

```ruby
class Event < ApplicationRecord
  include HasUuid
  include SoftDeletable
  include Searchable
  include Accountable
end
```

**In Controllers:**

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  include Filterable
end
```

## Checklist

- [ ] Test written first (RED)
- [ ] Uses `extend ActiveSupport::Concern`
- [ ] `included` block for callbacks/validations/scopes
- [ ] `class_methods` block for class-level methods
- [ ] Instance methods outside blocks
- [ ] Single responsibility (one purpose per concern)
- [ ] Well-named (describes what it adds: `HasUuid`, `SoftDeletable`, `Searchable`)
- [ ] Database-agnostic (no PostgreSQL-specific SQL like ILIKE)
- [ ] All tests GREEN
