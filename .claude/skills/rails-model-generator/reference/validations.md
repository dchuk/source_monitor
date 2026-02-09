# Rails Validation Patterns Reference

## Standard Validations

### Presence

```ruby
validates :name, presence: true
validates :email, presence: { message: "is required" }
```

**Test:**
```ruby
test "requires name" do
  record = Model.new(valid_attributes.except(:name))
  assert_not record.valid?
  assert record.errors[:name].any?
end
```

### Uniqueness

```ruby
validates :email, uniqueness: true
validates :email, uniqueness: { case_sensitive: false }
validates :slug, uniqueness: { scope: :organization_id }
validates :email, uniqueness: { conditions: -> { where(deleted_at: nil) } }
```

**Test:**
```ruby
test "requires unique email" do
  existing = users(:one)
  record = User.new(email: existing.email, password: "password123", account: accounts(:one))
  assert_not record.valid?
  assert record.errors[:email].any?
end

test "requires unique slug scoped to organization" do
  existing = records(:one)
  record = Record.new(slug: existing.slug, organization: existing.organization)
  assert_not record.valid?
  assert record.errors[:slug].any?
end
```

### Length

```ruby
validates :name, length: { maximum: 100 }
validates :bio, length: { minimum: 10, maximum: 500 }
validates :pin, length: { is: 4 }
validates :tags, length: { in: 1..5 }
```

**Test:**
```ruby
test "rejects name longer than 100 characters" do
  record = Model.new(valid_attributes.merge(name: "a" * 101))
  assert_not record.valid?
  assert record.errors[:name].any?
end

test "accepts name within 100 characters" do
  record = Model.new(valid_attributes.merge(name: "a" * 100))
  assert record.valid?
end
```

### Format

```ruby
validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
validates :phone, format: { with: /\A\+?[\d\s-]+\z/ }
validates :slug, format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
```

**Test:**
```ruby
test "accepts valid email format" do
  record = Model.new(valid_attributes.merge(email: "test@example.com"))
  assert record.valid?
end

test "rejects invalid email format" do
  record = Model.new(valid_attributes.merge(email: "invalid-email"))
  assert_not record.valid?
  assert record.errors[:email].any?
end
```

### Numericality

```ruby
validates :age, numericality: { only_integer: true, greater_than: 0 }
validates :price, numericality: { greater_than_or_equal_to: 0 }
validates :quantity, numericality: { only_integer: true, in: 1..100 }
```

**Test:**
```ruby
test "requires positive integer for age" do
  record = Model.new(valid_attributes.merge(age: -1))
  assert_not record.valid?
  assert record.errors[:age].any?
end

test "rejects non-integer age" do
  record = Model.new(valid_attributes.merge(age: 1.5))
  assert_not record.valid?
end
```

### Inclusion/Exclusion

```ruby
validates :status, inclusion: { in: %w[draft published archived] }
validates :role, inclusion: { in: :allowed_roles }
validates :username, exclusion: { in: %w[admin root system] }
```

**Test:**
```ruby
test "accepts valid status values" do
  %w[draft published archived].each do |status|
    record = Model.new(valid_attributes.merge(status: status))
    assert record.valid?, "Expected #{status} to be valid"
  end
end

test "rejects invalid status values" do
  record = Model.new(valid_attributes.merge(status: "invalid"))
  assert_not record.valid?
  assert record.errors[:status].any?
end

test "rejects reserved usernames" do
  %w[admin root system].each do |username|
    record = Model.new(valid_attributes.merge(username: username))
    assert_not record.valid?, "Expected #{username} to be invalid"
  end
end
```

### Acceptance

```ruby
validates :terms, acceptance: true
validates :terms, acceptance: { accept: ['yes', 'true', '1'] }
```

### Confirmation

```ruby
validates :password, confirmation: true
# Requires :password_confirmation attribute in form
```

## Conditional Validations

### With If/Unless

```ruby
validates :phone, presence: true, if: :requires_phone?
validates :company, presence: true, unless: :individual?
validates :bio, length: { minimum: 50 }, if: -> { featured? }
```

**Test:**
```ruby
test "requires phone when requires_phone? is true" do
  record = Model.new(valid_attributes.except(:phone))
  record.stub(:requires_phone?, true) do
    assert_not record.valid?
    assert record.errors[:phone].any?
  end
end

test "does not require phone when requires_phone? is false" do
  record = Model.new(valid_attributes.except(:phone))
  record.stub(:requires_phone?, false) do
    assert record.valid?
  end
end
```

### With On (Context)

```ruby
validates :password, presence: true, on: :create
validates :reason, presence: true, on: :archive
```

**Test:**
```ruby
test "requires password on create" do
  record = Model.new(valid_attributes.except(:password))
  assert_not record.valid?
  assert record.errors[:password].any?
end
```

## Custom Validations

### Custom Method

```ruby
class User < ApplicationRecord
  validate :email_domain_allowed

  private

  def email_domain_allowed
    return if email.blank?

    domain = email.split('@').last
    unless allowed_domains.include?(domain)
      errors.add(:email, "domain is not allowed")
    end
  end
end
```

**Test:**
```ruby
test "accepts allowed email domain" do
  user = User.new(valid_attributes.merge(email: "test@allowed.com"))
  assert user.valid?
end

test "rejects disallowed email domain" do
  user = User.new(valid_attributes.merge(email: "test@blocked.com"))
  assert_not user.valid?
  assert_includes user.errors[:email], "domain is not allowed"
end
```

### Custom Validator Class

```ruby
# app/validators/email_domain_validator.rb
class EmailDomainValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    domain = value.split('@').last
    unless options[:allowed].include?(domain)
      record.errors.add(attribute, options[:message] || "domain not allowed")
    end
  end
end

# Usage in model:
validates :email, email_domain: { allowed: %w[company.com], message: "must be company email" }
```

## Association Validations

```ruby
validates :organization, presence: true
validates_associated :profile  # Validates the associated record too

# With nested attributes
accepts_nested_attributes_for :addresses, allow_destroy: true
validates :addresses, length: { minimum: 1, message: "must have at least one address" }
```

## Database-Level Constraints

Always pair validations with database constraints:

```ruby
# Migration
add_column :users, :email, :string, null: false
add_index :users, :email, unique: true
add_check_constraint :users, 'age >= 0', name: 'age_non_negative'

# Model
validates :email, presence: true, uniqueness: true
validates :age, numericality: { greater_than_or_equal_to: 0 }
```

## Common Email Regex Patterns

```ruby
# Simple (recommended for most cases)
URI::MailTo::EMAIL_REGEXP

# More permissive
/\A[^@\s]+@[^@\s]+\z/
```

## Performance Tips

1. **Order validations by cost**: Put cheap validations first
2. **Use `on:` to skip validations**: Don't validate password on every save
3. **Avoid N+1 in custom validations**: Cache lookups
4. **Use database constraints**: They're faster than Rails validations
