---
name: database-migrations
description: Creates safe database migrations with proper indexes and rollback strategies. Use when creating tables, adding columns, creating indexes, handling zero-downtime migrations, or when user mentions migrations, schema changes, or database structure.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Database Migration Patterns for Rails 8

## Overview

Safe database migrations are critical for production stability:
- Zero-downtime deployments
- Reversible migrations
- Proper indexing
- Data integrity constraints

## Quick Start

```bash
bin/rails generate migration AddStatusToEvents status:integer
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:migrate:status
```

## Safety Checklist

```
Migration Safety:
- [ ] Migration is reversible (has down or uses change)
- [ ] Large tables use batching for updates
- [ ] Indexes added concurrently (if needed)
- [ ] Foreign keys have indexes
- [ ] NOT NULL added in two steps (for existing columns)
- [ ] Default values don't lock table
- [ ] Tested rollback locally
```

## Safe Migration Patterns

### Pattern 1: Add Column (Safe)

```ruby
class AddStatusToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :status, :integer, default: 0, null: false
  end
end
```

### Pattern 2: Add Column with NOT NULL (Two-Step)

For existing tables with data, add NOT NULL in two migrations:

```ruby
# Step 1: Add column with default (allows NULL temporarily)
class AddPriorityToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :priority, :integer, default: 0
  end
end

# Step 2: Add NOT NULL constraint after backfill
class AddNotNullToTasksPriority < ActiveRecord::Migration[8.0]
  def change
    change_column_null :tasks, :priority, false
  end
end
```

### Pattern 3: Add Index (Production Safe)

```ruby
class AddIndexToEventsStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :events, :status, algorithm: :concurrently, if_not_exists: true
  end
end
```

### Pattern 4: Add Foreign Key with Index

```ruby
class AddAccountToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :account, null: false, foreign_key: true, index: true
  end
end
```

### Pattern 5: Rename Column

```ruby
class RenameNameToTitleOnEvents < ActiveRecord::Migration[8.0]
  def change
    rename_column :events, :name, :title
  end
end
```

### Pattern 6: Remove Column

First remove references in code, then migrate:

```ruby
class RemoveLegacyFieldFromEvents < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :events, :legacy_field, :string }
  end
end
```

### Pattern 7: Add Enum Column

```ruby
class AddStatusEnumToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :status, :integer, default: 0, null: false
    add_index :orders, :status
  end
end
```

In model:
```ruby
class Order < ApplicationRecord
  enum :status, { pending: 0, confirmed: 1, shipped: 2, delivered: 3, cancelled: 4 }
end
```

### Pattern 8: Create Table with State Record

For app-wide configuration (single-row tables):

```ruby
class CreateAppConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :app_configs do |t|
      t.string :site_name, null: false, default: "My App"
      t.boolean :maintenance_mode, null: false, default: false
      t.text :settings
      t.timestamps
    end
  end
end
```

## Dangerous Operations (Avoid)

### DON'T: Change Column Type Directly

```ruby
# DANGEROUS - can lose data or lock table
change_column :events, :budget, :decimal  # DON'T DO THIS
```

### DO: Add New Column, Migrate Data, Remove Old

```ruby
# Step 1: Add new column
class AddBudgetDecimalToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :budget_decimal, :decimal, precision: 10, scale: 2
  end
end

# Step 2: Backfill data
class BackfillEventsBudget < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    Event.in_batches.update_all("budget_decimal = budget")
  end

  def down
    # Data migration, no rollback needed
  end
end

# Step 3: Remove old column (after code updated)
class RemoveOldBudgetFromEvents < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :events, :budget, :integer }
    rename_column :events, :budget_decimal, :budget
  end
end
```

## Data Migrations

### Safe Backfill Pattern

```ruby
class BackfillEventStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    Event.unscoped.in_batches(of: 1000) do |batch|
      batch.where(status: nil).update_all(status: 0)
      sleep(0.1) # Reduce database load
    end
  end

  def down
    # No rollback for data migration
  end
end
```

## Index Strategies

### Composite Indexes

```ruby
# For queries: WHERE account_id = ? AND status = ?
add_index :events, [:account_id, :status]

# Order matters! Left-to-right prefix matching:
# Helps: WHERE account_id = ? AND status = ?
# Helps: WHERE account_id = ?
# Does NOT help: WHERE status = ?
```

### Partial Indexes

```ruby
# Index only active records
add_index :events, :event_date, where: "status = 0", name: "index_events_on_date_active"

# Index only non-null values
add_index :users, :reset_token, where: "reset_token IS NOT NULL"
```

### Unique Indexes

```ruby
add_index :users, :email, unique: true
add_index :event_vendors, [:event_id, :vendor_id], unique: true
```

## Foreign Keys

```ruby
class AddForeignKeys < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :venue, foreign_key: true
    add_foreign_key :events, :users, column: :organizer_id

    # ON DELETE options
    add_foreign_key :comments, :posts, on_delete: :cascade
    add_foreign_key :posts, :users, column: :author_id, on_delete: :nullify
  end
end
```

## Testing Migrations

### Schema Integrity Test

```ruby
# test/db/schema_test.rb
require "test_helper"

class SchemaTest < ActiveSupport::TestCase
  test "all foreign keys have indexes" do
    connection = ActiveRecord::Base.connection

    connection.tables.each do |table|
      foreign_keys = connection.foreign_keys(table)
      indexes = connection.indexes(table)

      foreign_keys.each do |fk|
        indexed = indexes.any? { |idx| idx.columns.first == fk.column }
        assert indexed, "Missing index for #{fk.column} on #{table}"
      end
    end
  end
end
```

### Rollback Test (CLI)

```bash
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:migrate
bin/rails db:migrate:status
```

## Reversible Migrations

### Using up/down (Manual Reversal)

```ruby
class ChangeEventsStructure < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      ALTER TABLE events ADD CONSTRAINT check_positive_budget
      CHECK (budget_cents >= 0)
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE events DROP CONSTRAINT check_positive_budget
    SQL
  end
end
```

### Irreversible Migrations

```ruby
class DropLegacyTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :legacy_events
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore dropped table"
  end
end
```

## Performance Tips

```ruby
# DON'T - Locks entire table
add_index :large_table, :column

# DO - Non-blocking
disable_ddl_transaction!
add_index :large_table, :column, algorithm: :concurrently

# DON'T - Updates all at once
Event.update_all(status: 0)

# DO - Updates in batches
Event.in_batches(of: 1000) do |batch|
  batch.update_all(status: 0)
end
```

## Checklist

- [ ] Migration is reversible
- [ ] Indexes on foreign keys
- [ ] Concurrent index creation for large tables
- [ ] NOT NULL added safely (two-step)
- [ ] Data migrations use batching
- [ ] Tested rollback locally
- [ ] No table locks during deploy
