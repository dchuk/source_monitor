---
name: form-object-patterns
description: Creates form objects for complex form handling with TDD. Use when building multi-model forms, search forms, wizard forms, or when user mentions form objects, complex forms, virtual models, or non-persisted forms.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Form Object Patterns for Rails 8

## Overview

Form objects encapsulate complex form logic:
- Multi-model forms (user + profile + address)
- Search/filter forms (non-persisted)
- Wizard/multi-step forms
- Virtual attributes with validation
- Decoupled from ActiveRecord models

## When to Use Form Objects

| Scenario | Use Form Object? |
|----------|-----------------|
| Single model CRUD | No (use model) |
| Multi-model creation | Yes |
| Complex validations across models | Yes |
| Search/filter forms | Yes |
| Wizard/multi-step forms | Yes |
| API params transformation | Yes |
| Contact forms (no persistence) | Yes |

## TDD Workflow

```
Form Object Progress:
- [ ] Step 1: Define form requirements
- [ ] Step 2: Write form object test (RED)
- [ ] Step 3: Run test (fails)
- [ ] Step 4: Create form object
- [ ] Step 5: Run test (GREEN)
- [ ] Step 6: Wire up controller
- [ ] Step 7: Create view form
```

## Base Form Class

```ruby
# app/forms/application_form.rb
class ApplicationForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  def self.model_name
    ActiveModel::Name.new(self, nil, name.chomp("Form"))
  end

  def persisted?
    false
  end

  def save
    return false unless valid?
    persist!
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  private

  def persist!
    raise NotImplementedError
  end
end
```

## Pattern 1: Multi-Model Registration Form

### Test First (RED)

```ruby
# test/forms/registration_form_test.rb
require "test_helper"

class RegistrationFormTest < ActiveSupport::TestCase
  test "validates presence of email" do
    form = RegistrationForm.new(email: "")
    assert_not form.valid?
    assert_includes form.errors[:email], "can't be blank"
  end

  test "validates presence of password" do
    form = RegistrationForm.new(password: "")
    assert_not form.valid?
    assert_includes form.errors[:password], "can't be blank"
  end

  test "validates password minimum length" do
    form = RegistrationForm.new(password: "short")
    assert_not form.valid?
    assert form.errors[:password].any? { |e| e.include?("too short") }
  end

  test "#save with valid params returns true" do
    form = RegistrationForm.new(
      email: "user@example.com",
      password: "password123",
      password_confirmation: "password123",
      company_name: "Acme Inc"
    )

    assert form.save
  end

  test "#save creates a user" do
    form = RegistrationForm.new(
      email: "new-user@example.com",
      password: "password123",
      password_confirmation: "password123",
      company_name: "Acme Inc"
    )

    assert_difference("User.count", 1) { form.save }
  end

  test "#save creates an account" do
    form = RegistrationForm.new(
      email: "new-account@example.com",
      password: "password123",
      password_confirmation: "password123",
      company_name: "Acme Inc"
    )

    assert_difference("Account.count", 1) { form.save }
  end

  test "#save associates user with account" do
    form = RegistrationForm.new(
      email: "assoc@example.com",
      password: "password123",
      password_confirmation: "password123",
      company_name: "Acme Inc"
    )
    form.save
    assert_equal form.user.account, form.account
  end

  test "#save with invalid params returns false" do
    form = RegistrationForm.new(email: "", password: "short")
    assert_not form.save
  end

  test "#save with invalid params does not create records" do
    form = RegistrationForm.new(email: "", password: "short")
    assert_no_difference("User.count") { form.save }
  end

  test "#save with duplicate email returns false" do
    existing = users(:one)
    form = RegistrationForm.new(
      email: existing.email_address,
      password: "password123",
      password_confirmation: "password123",
      company_name: "Acme Inc"
    )

    assert_not form.save
    assert_includes form.errors[:email], "has already been taken"
  end
end
```

### Implementation (GREEN)

```ruby
# app/forms/registration_form.rb
class RegistrationForm < ApplicationForm
  attribute :email, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :company_name, :string
  attribute :phone, :string

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }
  validates :password_confirmation, presence: true
  validates :company_name, presence: true
  validate :passwords_match
  validate :email_unique

  attr_reader :user, :account

  private

  def persist!
    ActiveRecord::Base.transaction do
      @account = Account.create!(name: company_name)
      @user = User.create!(
        email_address: email,
        password: password,
        account: @account,
        phone: phone
      )
    end
  end

  def passwords_match
    return if password == password_confirmation
    errors.add(:password_confirmation, "doesn't match password")
  end

  def email_unique
    return unless User.exists?(email_address: email&.downcase)
    errors.add(:email, "has already been taken")
  end
end
```

## Pattern 2: Search/Filter Form

### Test First

```ruby
# test/forms/event_search_form_test.rb
require "test_helper"

class EventSearchFormTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
  end

  test "#results returns all account events without filters" do
    form = EventSearchForm.new(account: @account, params: {})
    results = form.results

    results.each do |event|
      assert_equal @account.id, event.account_id
    end
  end

  test "#results excludes other account events" do
    form = EventSearchForm.new(account: @account, params: {})
    other_event = events(:other_account)

    assert_not_includes form.results, other_event
  end

  test "#results filters by event_type" do
    form = EventSearchForm.new(account: @account, params: { event_type: "wedding" })
    form.results.each do |event|
      assert_equal "wedding", event.event_type
    end
  end

  test "#any_filters? returns true with filters" do
    form = EventSearchForm.new(account: @account, params: { query: "test" })
    assert form.any_filters?
  end

  test "#any_filters? returns false without filters" do
    form = EventSearchForm.new(account: @account, params: {})
    assert_not form.any_filters?
  end
end
```

### Implementation

```ruby
# app/forms/event_search_form.rb
class EventSearchForm < ApplicationForm
  attribute :query, :string
  attribute :event_type, :string
  attribute :status, :string
  attribute :start_date, :date
  attribute :end_date, :date

  attr_reader :account

  def initialize(account:, params: {})
    @account = account
    super(params)
  end

  def results
    scope = account.events
    scope = apply_search(scope)
    scope = apply_type_filter(scope)
    scope = apply_status_filter(scope)
    scope = apply_date_filter(scope)
    scope.order(event_date: :desc)
  end

  def any_filters?
    [query, event_type, status, start_date, end_date].any?(&:present?)
  end

  private

  def apply_search(scope)
    return scope if query.blank?
    scope.where("name LIKE :q OR description LIKE :q", q: "%#{sanitize_like(query)}%")
  end

  def apply_type_filter(scope)
    return scope if event_type.blank?
    scope.where(event_type: event_type)
  end

  def apply_status_filter(scope)
    return scope if status.blank?
    scope.where(status: status)
  end

  def apply_date_filter(scope)
    scope = scope.where("event_date >= ?", start_date) if start_date.present?
    scope = scope.where("event_date <= ?", end_date) if end_date.present?
    scope
  end

  def sanitize_like(term)
    term.gsub(/[%_]/) { |x| "\\#{x}" }
  end
end
```

## Pattern 3: Wizard/Multi-Step Form

```ruby
# app/forms/wizard/base_form.rb
module Wizard
  class BaseForm < ApplicationForm
    def self.steps
      raise NotImplementedError
    end

    def current_step
      raise NotImplementedError
    end

    def first_step?
      current_step == self.class.steps.first
    end

    def last_step?
      current_step == self.class.steps.last
    end

    def progress_percentage
      steps = self.class.steps
      ((steps.index(current_step) + 1).to_f / steps.size * 100).round
    end
  end
end
```

## Controller Integration

```ruby
class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    @form = RegistrationForm.new
  end

  def create
    @form = RegistrationForm.new(registration_params)

    if @form.save
      start_new_session_for(@form.user)
      redirect_to dashboard_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:registration).permit(
      :email, :password, :password_confirmation,
      :company_name, :phone
    )
  end
end
```

## Checklist

- [ ] Test written first (RED)
- [ ] Extends `ApplicationForm` or includes `ActiveModel::Model`
- [ ] Attributes declared with types
- [ ] Validations defined
- [ ] `#save` method with transaction (if multi-model)
- [ ] Controller uses form object
- [ ] View uses `form_with model: @form`
- [ ] Error handling in place
- [ ] All tests GREEN
