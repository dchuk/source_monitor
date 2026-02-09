---
name: rails-query-object
description: Creates query objects for complex database queries following TDD. Use when encapsulating complex queries, aggregating statistics, building reports, or when user mentions queries, stats, dashboards, or data aggregation.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Rails Query Object Generator (TDD)

Creates query objects that encapsulate complex database queries with tests first.

## Quick Start

1. Write failing test in `test/queries/`
2. Run test to confirm RED
3. Implement query object in `app/queries/`
4. Run test to confirm GREEN

## When to Use Query Objects vs Scopes

| Scenario | Use |
|----------|-----|
| Simple WHERE clause | **Scope** on the model |
| Single-condition filter | **Scope** on the model |
| Multi-table joins with conditions | **Query object** |
| Dashboard aggregations | **Query object** |
| Report generation | **Query object** |
| Queries needing constructor params | **Query object** |
| Reusable across controllers | **Query object** |

**Rule of thumb:** If the query fits in one line and needs no context, use a scope. If it needs parameters, joins multiple tables, or returns computed data, use a query object.

## Project Conventions

Query objects in this project:
- Accept context via constructor (`user:` or `account:`)
- Return `ActiveRecord::Relation` for chainability OR `Hash` for aggregations
- Have a `call` method for primary operation
- Support multi-tenancy (scoped to account)

## TDD Workflow

### Step 1: Create Query Test (RED)

```ruby
# test/queries/stale_leads_query_test.rb
require "test_helper"

class StaleLeadsQueryTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @other_account = accounts(:two)
  end

  test "requires an account parameter" do
    assert_raises(ArgumentError) { StaleLeadsQuery.new }
  end

  test "#call returns ActiveRecord::Relation" do
    query = StaleLeadsQuery.new(account: @account)
    assert_kind_of ActiveRecord::Relation, query.call
  end

  test "#call returns only leads for the account (multi-tenant)" do
    own_lead = leads(:stale_one)
    other_lead = leads(:other_account_stale)

    results = StaleLeadsQuery.new(account: @account).call

    assert_includes results, own_lead
    assert_not_includes results, other_lead
  end

  test "#call returns only stale leads" do
    stale = leads(:stale_one)
    fresh = leads(:fresh_one)

    results = StaleLeadsQuery.new(account: @account).call

    assert_includes results, stale
    assert_not_includes results, fresh
  end

  test "multi-tenant isolation" do
    other_query = StaleLeadsQuery.new(account: @other_account)
    own_query = StaleLeadsQuery.new(account: @account)

    assert_empty(other_query.call.where(id: leads(:stale_one).id))
    assert_not_empty(own_query.call.where(id: leads(:stale_one).id))
  end
end
```

### Step 2: Run Test (Confirm RED)

```bash
bin/rails test test/queries/stale_leads_query_test.rb
```

### Step 3: Implement Query Object (GREEN)

```ruby
# app/queries/stale_leads_query.rb
class StaleLeadsQuery
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  def call
    account.leads.stale
  end
end
```

### Step 4: Run Test (Confirm GREEN)

```bash
bin/rails test test/queries/stale_leads_query_test.rb
```

## Query Object Patterns

### Pattern 1: Simple Filtered Query

```ruby
# app/queries/stale_leads_query.rb
class StaleLeadsQuery
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  def call
    account.leads.stale
  end
end
```

### Pattern 2: Aggregation Query (Multiple Methods)

```ruby
# app/queries/dashboard_stats_query.rb
class DashboardStatsQuery
  attr_reader :user, :account

  def initialize(user:)
    @user = user
    @account = user.account
  end

  def upcoming_events(limit: 3)
    account.events
      .where("event_date >= ?", Date.today)
      .order(event_date: :asc)
      .limit(limit)
  end

  def pending_commissions_total
    EventVendor
      .joins(:event)
      .where(events: { account_id: account.id })
      .where(commission_status: :to_invoice)
      .sum(:commission_value)
  end

  def top_vendors(limit: 5)
    account.vendors
      .left_joins(:event_vendors)
      .select("vendors.*, COUNT(event_vendors.id) as events_count")
      .group("vendors.id")
      .order("events_count DESC")
      .limit(limit)
  end

  def leads_by_status
    account.leads.group(:status).count
  end
end
```

### Pattern 3: Grouping Query

```ruby
# app/queries/leads_by_status_query.rb
class LeadsByStatusQuery
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  def call
    leads = account.leads.order(created_at: :desc)
    result = Lead.statuses.keys.map(&:to_sym).index_with { [] }

    leads.group_by(&:status).each do |status, status_leads|
      result[status.to_sym] = status_leads
    end

    result
  end
end
```

### Testing Aggregation Queries

```ruby
# test/queries/dashboard_stats_query_test.rb
require "test_helper"

class DashboardStatsQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @query = DashboardStatsQuery.new(user: @user)
  end

  test "#upcoming_events returns future events only" do
    results = @query.upcoming_events
    results.each do |event|
      assert event.event_date >= Date.today
    end
  end

  test "#upcoming_events respects limit" do
    results = @query.upcoming_events(limit: 2)
    assert results.size <= 2
  end

  test "#leads_by_status returns hash of status to count" do
    result = @query.leads_by_status
    assert_kind_of Hash, result
  end

  test "scoped to user account only" do
    other_user = users(:other_account)
    other_query = DashboardStatsQuery.new(user: other_user)

    own_events = @query.upcoming_events
    other_events = other_query.upcoming_events

    own_events.each do |event|
      assert_equal @user.account_id, event.account_id
    end
  end
end
```

## Usage in Controllers

```ruby
# Simple query
def index
  @leads_by_status = LeadsByStatusQuery.new(account: current_account).call
end

# Aggregation query with presenter
def index
  stats_query = DashboardStatsQuery.new(user: current_user)
  @stats = DashboardStatsPresenter.new(stats_query)
end
```

## Directory Structure

```
app/queries/
  stale_leads_query.rb
  leads_by_status_query.rb
  dashboard_stats_query.rb
  events/
    upcoming_query.rb
    by_vendor_query.rb
test/queries/
  stale_leads_query_test.rb
  dashboard_stats_query_test.rb
```

## Checklist

- [ ] Test written first (RED)
- [ ] Constructor accepts context (`user:` or `account:`)
- [ ] Multi-tenant isolation tested
- [ ] Return type documented
- [ ] Methods have clear, descriptive names
- [ ] Complex queries use `.includes()` to prevent N+1
- [ ] Database-agnostic (no PostgreSQL-specific SQL)
- [ ] All tests GREEN
