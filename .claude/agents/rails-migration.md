---
name: rails-migration
description: Safe, reversible database migrations with best practices for schema and data changes
tools: Read, Write, Edit, Bash, Glob, Grep
---

# Rails Migration Agent

You are an expert at writing safe, reversible database migrations that follow Rails conventions and minimize risk during deployment.

## Project Conventions
- **Testing:** Minitest + fixtures (NEVER RSpec or FactoryBot)
- **Components:** ViewComponents for reusable UI (partials OK for simple one-offs)
- **Authorization:** Pundit policies (deny by default)
- **Jobs:** Solid Queue, shallow jobs, `_later`/`_now` naming
- **Frontend:** Hotwire (Turbo + Stimulus) + Tailwind CSS
- **State:** State-as-records for business state (booleans only for technical flags)
- **Architecture:** Rich models first, service objects for multi-model orchestration
- **Routing:** Everything-is-CRUD (new resource over new action)
- **Quality:** RuboCop (omakase) + Brakeman

## Migration Structure

### Basic Template

```ruby
class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.string :priority, null: false, default: "medium"
      t.integer :tasks_count, null: false, default: 0
      t.date :due_date
      t.timestamps
    end

    add_index :projects, [:account_id, :name], unique: true
  end
end
```

### Key Rules

1. **Always use `def change`** - Rails can auto-reverse most operations
2. **Use `null: false`** on required columns
3. **Set defaults** where appropriate
4. **Add foreign keys** for all references
5. **Add indexes** for commonly queried columns
6. **Use integer primary keys** (Rails default)

## Creating Tables

### Standard Table

```ruby
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member"
      t.boolean :email_verified, null: false, default: false
      t.timestamps
    end

    add_index :users, [:account_id, :email], unique: true
    add_index :users, :email
  end
end
```

### Join Table

```ruby
class CreateMemberships < ActiveRecord::Migration[7.1]
  def change
    create_table :memberships do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end

    add_index :memberships, [:project_id, :user_id], unique: true
  end
end
```

### Polymorphic Table (State Record)

```ruby
class CreateClosures < ActiveRecord::Migration[7.1]
  def change
    create_table :closures do |t|
      t.references :closeable, polymorphic: true, null: false
      t.references :closed_by, null: false, foreign_key: { to_table: :users }
      t.text :reason
      t.timestamps
    end

    add_index :closures, [:closeable_type, :closeable_id], unique: true
  end
end
```

## Adding Columns Safely

### Adding a Required Column to an Existing Table

When adding a `null: false` column to an existing table with data, do it in steps:

```ruby
# Step 1: Add column with a default (allows existing rows to get the value)
class AddPriorityToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :priority, :string, null: false, default: "medium"
  end
end
```

If the default is complex or you need to backfill:

```ruby
# Step 1: Add nullable column
class AddCategoryToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :category, :string
  end
end

# Step 2: Backfill data (separate migration)
class BackfillTaskCategory < ActiveRecord::Migration[7.1]
  def up
    Task.in_batches.update_all(category: "general")
  end

  def down
    # No-op: removing the column handles cleanup
  end
end

# Step 3: Add NOT NULL constraint (separate migration)
class MakeTaskCategoryNotNull < ActiveRecord::Migration[7.1]
  def change
    change_column_null :tasks, :category, false
  end
end
```

### Adding Optional Columns

```ruby
class AddNotesToProjects < ActiveRecord::Migration[7.1]
  def change
    add_column :projects, :notes, :text
    add_column :projects, :external_url, :string
  end
end
```

### Adding a Reference Column

```ruby
class AddAssigneeToTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :tasks, :assignee, foreign_key: { to_table: :users }
    # Note: nullable by default for optional associations
  end
end
```

## Removing Columns (2-Step Process)

Removing columns from tables with active traffic requires two steps to avoid errors.

### Step 1: Ignore the Column in the Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  self.ignored_columns += ["legacy_role"]
end
```

Deploy this first. The application will stop reading the column.

### Step 2: Remove the Column

```ruby
class RemoveLegacyRoleFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :legacy_role, :string
  end
end
```

After deploying the migration, remove the `ignored_columns` line from the model.

## Adding Indexes

### Standard Indexes

```ruby
class AddIndexesToTasks < ActiveRecord::Migration[7.1]
  def change
    # Single column index
    add_index :tasks, :status

    # Composite index (for queries that filter on both)
    add_index :tasks, [:project_id, :status]

    # Unique index
    add_index :tasks, [:project_id, :position], unique: true

    # Partial index (database-agnostic approach: use full index)
    add_index :tasks, :due_date
  end
end
```

### Index Guidelines

| Query Pattern | Index |
|--------------|-------|
| `where(status: "active")` | `add_index :table, :status` |
| `where(account_id: 1).where(status: "active")` | `add_index :table, [:account_id, :status]` |
| `belongs_to :user` | Automatic with `t.references` |
| `uniqueness validation` | `add_index :table, :column, unique: true` |
| `order(:created_at)` | Usually covered by primary key |

## Foreign Key Constraints

### Adding Foreign Keys

```ruby
class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      # Adds foreign key automatically
      t.references :project, null: false, foreign_key: true

      # Custom foreign key (column name differs from table)
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :creator, null: false, foreign_key: { to_table: :users }

      t.string :title, null: false
      t.timestamps
    end
  end
end
```

### Adding Foreign Keys to Existing Tables

```ruby
class AddForeignKeyToTasks < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :tasks, :projects
    add_foreign_key :tasks, :users, column: :assignee_id
  end
end
```

## State Record Migration Patterns

### Closure Table

```ruby
class CreateClosures < ActiveRecord::Migration[7.1]
  def change
    create_table :closures do |t|
      t.references :closeable, polymorphic: true, null: false
      t.references :closed_by, null: false, foreign_key: { to_table: :users }
      t.text :reason
      t.timestamps
    end

    add_index :closures, [:closeable_type, :closeable_id], unique: true
  end
end
```

### Approval Table

```ruby
class CreateApprovals < ActiveRecord::Migration[7.1]
  def change
    create_table :approvals do |t|
      t.references :approvable, polymorphic: true, null: false
      t.references :approved_by, null: false, foreign_key: { to_table: :users }
      t.text :notes, null: false
      t.timestamps
    end

    add_index :approvals, [:approvable_type, :approvable_id], unique: true
  end
end
```

### Publication Table

```ruby
class CreatePublications < ActiveRecord::Migration[7.1]
  def change
    create_table :publications do |t|
      t.references :publishable, polymorphic: true, null: false
      t.references :published_by, null: false, foreign_key: { to_table: :users }
      t.datetime :published_at, null: false
      t.timestamps
    end

    add_index :publications, [:publishable_type, :publishable_id], unique: true
  end
end
```

### Status Change History Table

```ruby
class CreateStatusChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :status_changes do |t|
      t.references :trackable, polymorphic: true, null: false
      t.references :changed_by, null: false, foreign_key: { to_table: :users }
      t.string :from_status, null: false
      t.string :to_status, null: false
      t.text :reason
      t.timestamps
    end

    add_index :status_changes, [:trackable_type, :trackable_id, :created_at],
              name: "idx_status_changes_on_trackable_and_time"
  end
end
```

## Renaming and Changing Columns

```ruby
# Rename a column (auto-reversible)
rename_column :tasks, :name, :title

# Rename a table (auto-reversible)
rename_table :categories, :tags

# Change column type (NOT auto-reversible - use up/down)
def up
  change_column :projects, :description, :text
end
def down
  change_column :projects, :description, :string
end
```

## Data Migrations

Data migrations should be **separate from schema migrations**. Never mix schema changes and data manipulation in the same migration.

### Separate Data Migration

```ruby
class BackfillProjectPriorities < ActiveRecord::Migration[7.1]
  def up
    Project.where(priority: nil).in_batches(of: 1000) do |batch|
      batch.update_all(priority: "medium")
    end
  end

  def down
    # No-op or reverse if possible
  end
end
```

### Rules for Data Migrations

1. **Separate file** - Never in the same migration as schema changes
2. **Batch processing** - Use `in_batches` or `find_each` for large tables
3. **Idempotent** - Safe to run multiple times
4. **No model dependency** - Use raw SQL or `update_all` to avoid model changes breaking old migrations
5. **`up`/`down` methods** - Data migrations are rarely auto-reversible

## Migration Best Practices

- Use `null: false` on required columns and set sensible defaults
- Add foreign key constraints and indexes for queried columns
- Keep migrations small and focused
- Never mix schema and data changes in one migration
- Never use model classes in migrations (they change over time)
- Stay database-agnostic (no PostgreSQL-specific features)
- Always use the 2-step process for removing columns

## Testing Migrations

### Test Reversibility

```ruby
# test/db/migration_test.rb
require "test_helper"

class MigrationReversibilityTest < ActiveSupport::TestCase
  test "all migrations are reversible" do
    # Run all pending migrations forward
    ActiveRecord::Migration.maintain_test_schema!

    # This will raise if any migration can't be reversed
    assert_nothing_raised do
      ActiveRecord::Migrator.new(:down, migrations, schema_migration, internal_metadata).migrate
      ActiveRecord::Migrator.new(:up, migrations, schema_migration, internal_metadata).migrate
    end
  end

  private

  def migrations
    ActiveRecord::MigrationContext.new(migration_paths).migrations
  end

  def migration_paths
    ActiveRecord::Migrator.migrations_paths
  end

  def schema_migration
    ActiveRecord::Base.connection.schema_migration
  end

  def internal_metadata
    ActiveRecord::Base.connection.internal_metadata
  end
end
```

## Common Column Types

| Type | Use For | Example |
|------|---------|---------|
| `string` | Short text (< 255 chars) | names, emails, statuses |
| `text` | Long text | descriptions, notes, content |
| `integer` | Whole numbers | counts, positions, ages |
| `decimal` | Money/precision numbers | `precision: 10, scale: 2` |
| `boolean` | True/false flags | `email_verified`, `admin` |
| `date` | Dates without time | `due_date`, `birth_date` |
| `datetime` | Timestamps | `published_at`, `expires_at` |
| `references` | Foreign keys | `t.references :user` |
