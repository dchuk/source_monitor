---
name: sm-engine-migration
description: Migration conventions for the Source Monitor engine. Use when creating database migrations, adding columns, indexes, constraints, or modifying the schema for the Source Monitor engine.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Source Monitor Engine Migrations

## Table Naming Convention

All engine tables use the `sourcemon_` prefix:

| Model | Table Name |
|-------|-----------|
| Source | `sourcemon_sources` |
| Item | `sourcemon_items` |
| FetchLog | `sourcemon_fetch_logs` |
| ScrapeLog | `sourcemon_scrape_logs` |
| LogEntry | `sourcemon_log_entries` |
| ItemContent | `sourcemon_item_contents` |
| HealthCheckLog | `sourcemon_health_check_logs` |
| ImportSession | `sourcemon_import_sessions` |
| ImportHistory | `sourcemon_import_histories` |

The prefix comes from `SourceMonitor.config.models.table_name_prefix` (default: `"sourcemon_"`).

## Creating a Migration

```bash
bin/rails generate migration AddFieldToSourcemonSources field:type
```

### Naming Convention

Migration class names describe the change:

| Pattern | Example |
|---------|---------|
| Create table | `CreateSourceMonitorLogEntries` |
| Add column | `AddAdaptiveFetchingToggleToSources` |
| Add index | `AddCompositeIndexToLogEntries` |
| Add constraint | `AddFetchStatusCheckConstraint` |
| Multi-column | `AddHealthFieldsToSources` |
| Performance | `OptimizeSourceMonitorDatabasePerformance` |
| Modify constraint | `RefreshFetchStatusConstraint` |

## Table Creation Pattern

```ruby
# frozen_string_literal: true

class CreateSourceMonitorWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :sourcemon_widgets do |t|
      # Foreign keys reference engine tables by name
      t.references :source, null: false, foreign_key: { to_table: :sourcemon_sources }
      t.references :item, foreign_key: { to_table: :sourcemon_items }

      # Columns
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :count, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    # Indexes after create_table
    add_index :sourcemon_widgets, :name
    add_index :sourcemon_widgets, :active
    add_index :sourcemon_widgets, :started_at
  end
end
```

### Dynamic Table Names

Later migrations use `SourceMonitor.table_name_prefix` for consistency:

```ruby
create_table :"#{SourceMonitor.table_name_prefix}import_sessions" do |t|
  # ...
end

add_index :"#{SourceMonitor.table_name_prefix}import_sessions", :current_step
```

Both hardcoded `sourcemon_` and dynamic prefix are used in the codebase. For new migrations, prefer the dynamic approach.

## Foreign Key Conventions

**Always specify `to_table`** for foreign keys referencing engine tables:

```ruby
# Engine-to-engine FK
t.references :source, null: false, foreign_key: { to_table: :sourcemon_sources }
t.references :item, foreign_key: { to_table: :sourcemon_items }

# Engine-to-host-app FK (references host app's users table)
t.references :user, null: false, foreign_key: true

# Polymorphic reference (no FK constraint)
t.references :loggable, polymorphic: true, null: false,
  index: { name: "index_sourcemon_log_entries_on_loggable" }
```

## Index Conventions

### Standard Indexes

```ruby
# Single column
add_index :sourcemon_sources, :feed_url, unique: true
add_index :sourcemon_sources, :active
add_index :sourcemon_sources, :next_fetch_at

# Composite unique index
add_index :sourcemon_items, [:source_id, :guid], unique: true

# Named index (when auto-generated name is too long)
add_index :sourcemon_items, %i[source_id published_at created_at],
  name: "index_sourcemon_items_on_source_and_published_at"
```

### Concurrent Indexes (for zero-downtime)

```ruby
class AddCompositeIndexToLogEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :sourcemon_log_entries, [:started_at, :id],
      order: { started_at: :desc, id: :desc },
      name: "index_log_entries_on_started_at_desc_id_desc",
      algorithm: :concurrently
  end
end
```

### Conditional Index Creation

```ruby
unless index_exists?(:sourcemon_sources, :created_at)
  add_index :sourcemon_sources, :created_at, name: "index_sourcemon_sources_on_created_at"
end
```

## Column Patterns

### JSONB Columns

Always provide `null: false, default: {}` (or `default: []` for arrays):

```ruby
t.jsonb :metadata, null: false, default: {}
t.jsonb :scrape_settings, null: false, default: {}
t.jsonb :categories, null: false, default: []
t.jsonb :parsed_sources, null: false, default: []
```

### Boolean Columns

Always provide `null: false, default:`:

```ruby
t.boolean :active, null: false, default: true
t.boolean :success, null: false, default: false
t.boolean :scraping_enabled, null: false, default: false
```

### Counter Columns

```ruby
t.integer :items_count, null: false, default: 0
t.integer :failure_count, null: false, default: 0
t.integer :comments_count, null: false, default: 0
```

### Decimal Columns (for rates/thresholds)

```ruby
t.decimal :rolling_success_rate, precision: 5, scale: 4
t.decimal :health_auto_pause_threshold, precision: 5, scale: 4
```

## CHECK Constraints

### Adding a Constraint

```ruby
class AddFetchStatusCheckConstraint < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      ALTER TABLE sourcemon_sources
      ADD CONSTRAINT check_fetch_status_values
      CHECK (fetch_status IN ('idle', 'queued', 'fetching', 'failed'))
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE sourcemon_sources
      DROP CONSTRAINT check_fetch_status_values
    SQL
  end
end
```

### Modifying a Constraint

```ruby
class RefreshFetchStatusConstraint < ActiveRecord::Migration[8.0]
  ALLOWED_STATUSES = %w[idle queued fetching failed invalid].freeze
  PREVIOUS_STATUSES = %w[idle queued fetching failed].freeze

  def up
    replace_constraint(ALLOWED_STATUSES)
  end

  def down
    replace_constraint(PREVIOUS_STATUSES)
  end

  private

  def replace_constraint(statuses)
    quoted = statuses.map { |s| ActiveRecord::Base.connection.quote(s) }.join(", ")

    execute <<~SQL
      ALTER TABLE sourcemon_sources DROP CONSTRAINT IF EXISTS check_fetch_status_values
    SQL

    execute <<~SQL
      ALTER TABLE sourcemon_sources
      ADD CONSTRAINT check_fetch_status_values CHECK (fetch_status IN (#{quoted}))
    SQL
  end
end
```

## Data Migration Pattern

For migrations that backfill data, use anonymous ActiveRecord classes:

```ruby
reversible do |direction|
  direction.up do
    say_with_time "Backfilling sourcemon_log_entries" do
      source_class = Class.new(ActiveRecord::Base) { self.table_name = "sourcemon_fetch_logs" }
      target_class = Class.new(ActiveRecord::Base) { self.table_name = "sourcemon_log_entries" }

      source_class.find_each do |record|
        target_class.create!(
          source_id: record.source_id,
          # ... map fields ...
        )
      end
    end
  end
end
```

## Column Extraction Pattern

Moving columns from one table to a new table:

```ruby
class CreateSourceMonitorItemContents < ActiveRecord::Migration[8.0]
  def up
    create_table :sourcemon_item_contents do |t|
      t.references :item, null: false,
        foreign_key: { to_table: :sourcemon_items },
        index: { unique: true }
      t.text :scraped_html
      t.text :scraped_content
      t.timestamps(null: false)
    end

    # Migrate existing data
    execute <<~SQL
      INSERT INTO sourcemon_item_contents (item_id, scraped_html, scraped_content, created_at, updated_at)
      SELECT id, scraped_html, scraped_content, COALESCE(updated_at, CURRENT_TIMESTAMP), COALESCE(updated_at, CURRENT_TIMESTAMP)
      FROM sourcemon_items
      WHERE scraped_html IS NOT NULL OR scraped_content IS NOT NULL
    SQL

    # Remove old columns
    remove_column :sourcemon_items, :scraped_html, :text
    remove_column :sourcemon_items, :scraped_content, :text
  end

  def down
    add_column :sourcemon_items, :scraped_html, :text
    add_column :sourcemon_items, :scraped_content, :text

    execute <<~SQL
      UPDATE sourcemon_items items
      SET scraped_html = contents.scraped_html,
          scraped_content = contents.scraped_content
      FROM sourcemon_item_contents contents
      WHERE contents.item_id = items.id
    SQL

    drop_table :sourcemon_item_contents
  end
end
```

## Adding NOT NULL to Existing Columns

Clean up data before adding constraint:

```ruby
class AddNotNullConstraintsToItems < ActiveRecord::Migration[8.0]
  def up
    # Fix existing NULL values first
    execute <<~SQL
      UPDATE sourcemon_items
      SET guid = COALESCE(content_fingerprint, gen_random_uuid()::text)
      WHERE guid IS NULL
    SQL

    change_column_null :sourcemon_items, :guid, false
  end

  def down
    change_column_null :sourcemon_items, :guid, true
  end
end
```

## Bulk Column Changes

```ruby
class AddHealthFieldsToSources < ActiveRecord::Migration[8.0]
  def change
    change_table :sourcemon_sources, bulk: true do |t|
      t.decimal :rolling_success_rate, precision: 5, scale: 4
      t.string :health_status, null: false, default: "healthy"
      t.datetime :health_status_changed_at
      t.datetime :auto_paused_at
      t.datetime :auto_paused_until
      t.decimal :health_auto_pause_threshold, precision: 5, scale: 4
    end

    add_index :sourcemon_sources, :health_status
    add_index :sourcemon_sources, :auto_paused_until
  end
end
```

## Host App Installation

Engine migrations are installed in the host app via:

```bash
bin/rails source_monitor:install:migrations
bin/rails db:migrate
```

This copies migration files from the engine's `db/migrate/` into the host app's `db/migrate/` directory, preserving timestamps.

## Testing

Test migrations indirectly by testing the models and database constraints they create:

```ruby
test "database rejects invalid fetch_status values" do
  source = create_source!
  error = assert_raises(ActiveRecord::StatementInvalid) do
    source.update_columns(fetch_status: "bogus")
  end
  assert_match(/check_fetch_status_values/i, error.message)
end
```

## Checklist

- [ ] Table uses `sourcemon_` prefix
- [ ] Foreign keys specify `to_table:` for engine tables
- [ ] JSONB columns have `null: false, default: {}` (or `[]`)
- [ ] Boolean columns have `null: false, default:`
- [ ] Counter columns have `null: false, default: 0`
- [ ] Indexes have explicit names if auto-name would be too long
- [ ] Migration is reversible (or has explicit `up`/`down`)
- [ ] Data migrations use anonymous AR classes (not model constants)
- [ ] Concurrent indexes use `disable_ddl_transaction!` and `algorithm: :concurrently`
- [ ] CHECK constraints use raw SQL with `execute`
- [ ] Run: `bin/rails db:migrate && bin/rails db:rollback && bin/rails db:migrate`

## References

- [reference/migration-conventions.md](reference/migration-conventions.md) -- Complete table catalog and naming conventions
