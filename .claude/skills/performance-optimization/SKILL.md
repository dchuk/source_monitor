---
name: performance-optimization
description: Identifies and fixes Rails performance issues including N+1 queries, slow queries, and memory problems. Use when optimizing queries, fixing N+1 issues, improving response times, or when user mentions performance, slow, optimization, or Bullet gem.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Performance Optimization for Rails 8

## Overview

Performance optimization focuses on:
- N+1 query detection and prevention
- Query optimization with eager loading
- Database indexing
- Memory management
- Batch processing

## Quick Start

```ruby
# Gemfile
group :development, :test do
  gem "bullet"             # N+1 detection
  gem "rack-mini-profiler" # Request profiling
end
```

## Bullet Configuration

```ruby
# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.bullet_logger = true
  Bullet.console = true
  Bullet.rails_logger = true
end

# config/environments/test.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.raise = true  # Fail tests on N+1
end
```

## N+1 Query Problems

### The Problem

```ruby
# BAD: N+1 - 1 query for events, N queries for venues
@events = Event.all
@events.each { |e| e.venue.name }  # Query per event!
```

### The Solution

```ruby
# GOOD: 2 queries total
@events = Event.includes(:venue)
@events.each { |e| e.venue.name }  # No additional query
```

## Eager Loading Methods

| Method | Use When |
|--------|----------|
| `includes` | Most cases (Rails chooses strategy) |
| `preload` | Force separate queries, large datasets |
| `eager_load` | Filtering on association, need LEFT JOIN |
| `joins` | Only filtering, don't need association data |

```ruby
# Single association
Event.includes(:venue)

# Multiple
Event.includes(:venue, :organizer)

# Nested
Event.includes(venue: :address)

# Deep nesting
Event.includes(
  :venue, :organizer,
  vendors: [:category, :reviews],
  comments: :user
)
```

## Query Optimization Patterns

### Pattern 1: Scoped Eager Loading

```ruby
class Event < ApplicationRecord
  scope :with_details, -> {
    includes(:venue, :organizer, vendors: :category)
  }
end

# Controller
@events = Event.with_details.where(account: current_account)
```

### Pattern 2: Counter Caches

```ruby
# Migration
add_column :events, :comments_count, :integer, default: 0, null: false

# Model
class Comment < ApplicationRecord
  belongs_to :event, counter_cache: true
end

# Usage (no query)
event.comments_count
```

### Pattern 3: Select Only Needed Columns

```ruby
# BAD
User.all.map(&:name)

# GOOD
User.pluck(:name)

# For objects with limited columns
User.select(:id, :name, :email)
```

### Pattern 4: Batch Processing

```ruby
# BAD: Loads all records
Event.all.each { |e| process(e) }

# GOOD: Processes in batches
Event.find_each(batch_size: 500) { |e| process(e) }

# For updates
Event.in_batches(of: 1000) do |batch|
  batch.update_all(status: :archived)
end
```

### Pattern 5: Exists? vs Present?

```ruby
# BAD: Loads all records
if Event.where(status: :active).any?
if Event.where(status: :active).present?

# GOOD: SELECT 1 LIMIT 1
if Event.where(status: :active).exists?
```

### Pattern 6: Size vs Count vs Length

```ruby
# count: Always queries database
# size: Uses counter cache if available, else count
# length: Loads collection if not loaded

# Use size (handles both cases)
events.size
```

## Database Indexing

### When to Add Indexes

| Add Index For | Example |
|--------------|---------|
| Foreign keys | `account_id`, `user_id` |
| WHERE columns | `WHERE status = 'active'` |
| ORDER BY columns | `ORDER BY created_at DESC` |
| JOIN columns | `JOIN ON events.venue_id` |
| Unique constraints | `email`, `uuid` |

### Index Types

```ruby
add_index :events, :status                              # Single
add_index :events, [:account_id, :status]              # Composite
add_index :users, :email, unique: true                  # Unique
add_index :events, :event_date, where: "status = 0"    # Partial
```

## Testing for Performance

### N+1 Detection in Tests

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    Bullet.start_request if Bullet.enable?
  end

  teardown do
    if Bullet.enable?
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
  end
end
```

### Query Count Assertions

```ruby
# test/support/query_counter.rb
module QueryCounter
  def count_queries(&block)
    count = 0
    counter = ->(*, _) { count += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

# test/test_helper.rb
class ActiveSupport::TestCase
  include QueryCounter
end
```

```ruby
# test/models/event_test.rb
require "test_helper"

class EventPerformanceTest < ActiveSupport::TestCase
  test "with_details makes minimal queries" do
    query_count = count_queries do
      Event.with_details.where(account: accounts(:one)).each do |e|
        e.venue&.name
        e.organizer&.name
      end
    end

    # events + venues + organizers = 3 queries max
    assert query_count <= 3, "Expected <= 3 queries, got #{query_count}"
  end
end
```

### Missing Index Detection

```ruby
# test/db/schema_test.rb
require "test_helper"

class SchemaPerformanceTest < ActiveSupport::TestCase
  test "all foreign keys have indexes" do
    connection = ActiveRecord::Base.connection

    connection.tables.each do |table|
      columns = connection.columns(table)
      fk_columns = columns.select { |c| c.name.end_with?("_id") }
      indexes = connection.indexes(table)

      fk_columns.each do |col|
        indexed = indexes.any? { |idx| idx.columns.include?(col.name) }
        assert indexed, "Missing index: #{table}.#{col.name}"
      end
    end
  end
end
```

## Memory Optimization

```ruby
# BAD: Builds large array
Event.all.map(&:name).join(", ")

# GOOD: Streams results
Event.pluck(:name).join(", ")

# BAD: Instantiates all AR objects
Event.all.each { |e| e.update!(processed: true) }

# GOOD: Direct SQL update in batches
Event.in_batches.update_all(processed: true)
```

## Quick Fixes Reference

| Problem | Solution |
|---------|----------|
| N+1 on belongs_to | `includes(:association)` |
| N+1 on has_many | `includes(:association)` |
| Slow COUNT | Add counter_cache |
| Loading all columns | Use `select` or `pluck` |
| Large dataset iteration | Use `find_each` |
| Missing index on FK | Add index on `*_id` columns |
| Slow WHERE clause | Add index on filtered column |

## Checklist

- [ ] Bullet enabled in development/test
- [ ] No N+1 queries in critical paths
- [ ] Foreign keys have indexes
- [ ] Counter caches for frequent counts
- [ ] Eager loading in controllers
- [ ] Batch processing for large datasets
- [ ] All tests GREEN
