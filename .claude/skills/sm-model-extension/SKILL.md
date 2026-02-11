---
name: sm-model-extension
description: Use when extending SourceMonitor engine models from a host app, including adding concerns, validations, scopes, associations, and customizing table name prefixes via ModelExtensions.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-model-extension: Extend Engine Models from Host App

Add custom behavior to SourceMonitor engine models without monkey-patching.

## When to Use

- Adding associations, scopes, or methods to `Source`, `Item`, or other engine models
- Adding custom validations to engine models
- Changing the database table name prefix
- Understanding how `ModelExtensions.register` works
- Debugging model extension issues

## Extension Mechanism

SourceMonitor uses `ModelExtensions.register` to apply host-defined concerns and validations to engine models at load time. When `SourceMonitor.configure` runs, it calls `ModelExtensions.reload!` to re-apply all extensions.

### Flow

```
1. Host app defines concern modules and validations
2. config/initializers/source_monitor.rb registers them:
     config.models.source.include_concern "MyApp::SourceExtension"
     config.models.source.validate :custom_check
3. SourceMonitor.configure { |c| ... } runs
4. ModelExtensions.reload! applies all concerns and validations
5. Engine models now have the extended behavior
```

## Available Extension Points

### Extendable Models

| Config Accessor | Engine Model | DB Table |
|---|---|---|
| `config.models.source` | `SourceMonitor::Source` | `sourcemon_sources` |
| `config.models.item` | `SourceMonitor::Item` | `sourcemon_items` |
| `config.models.fetch_log` | `SourceMonitor::FetchLog` | `sourcemon_fetch_logs` |
| `config.models.scrape_log` | `SourceMonitor::ScrapeLog` | `sourcemon_scrape_logs` |
| `config.models.health_check_log` | `SourceMonitor::HealthCheckLog` | `sourcemon_health_check_logs` |
| `config.models.item_content` | `SourceMonitor::ItemContent` | `sourcemon_item_contents` |
| `config.models.log_entry` | `SourceMonitor::LogEntry` | `sourcemon_log_entries` |

### Table Name Prefix

```ruby
config.models.table_name_prefix = "sm_"  # Changes all tables from sourcemon_* to sm_*
```

Default: `"sourcemon_"`

### Including Concerns

Three forms supported:

```ruby
# 1. String (lazy constantization -- recommended for autoloaded modules)
config.models.source.include_concern "MyApp::SourceMonitor::SourceExtensions"

# 2. Module reference (immediate)
config.models.source.include_concern MyApp::SourceMonitor::SourceExtensions

# 3. Anonymous block (creates Module.new)
config.models.source.include_concern do
  has_many :tags, dependent: :destroy, foreign_key: :source_id
  scope :tagged, ->(tag) { joins(:tags).where(tags: { name: tag }) }
end
```

Concerns are deduplicated by signature -- including the same concern twice is safe.

### Adding Validations

Two forms:

```ruby
# 1. Symbol -- method name (must be defined in a concern or the model)
config.models.source.validate :enforce_custom_rules

# 2. Callable (proc/lambda) -- receives the record
config.models.source.validate ->(record) {
  record.errors.add(:url, "must be HTTPS") unless record.url&.start_with?("https://")
}

# With validation options
config.models.source.validate :check_plan_limits, on: :create
```

## Creating a Host Extension

### Step 1: Define the Concern

```ruby
# app/models/concerns/my_app/source_monitor/source_extensions.rb
module MyApp
  module SourceMonitor
    module SourceExtensions
      extend ActiveSupport::Concern

      included do
        # Associations
        has_many :source_tags, class_name: "MyApp::SourceTag",
          foreign_key: :source_monitor_source_id, dependent: :destroy

        # Scopes
        scope :by_team, ->(team_id) { where(team_id: team_id) }
        scope :premium, -> { where(premium: true) }

        # Callbacks
        after_create :notify_team
      end

      # Instance methods
      def team_name
        team&.name || "Unassigned"
      end

      private

      def notify_team
        TeamNotifier.source_added(self) if team_id.present?
      end
    end
  end
end
```

### Step 2: Register in Configuration

```ruby
# config/initializers/source_monitor.rb
SourceMonitor.configure do |config|
  config.models.source.include_concern "MyApp::SourceMonitor::SourceExtensions"
  config.models.source.validate :validate_team_assignment

  config.models.item.include_concern "MyApp::SourceMonitor::ItemExtensions"
end
```

### Step 3: Add Database Columns (if needed)

If your extension requires new columns on engine tables, create a migration in the host app:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_team_to_sourcemon_sources.rb
class AddTeamToSourcemonSources < ActiveRecord::Migration[8.0]
  def change
    add_column :sourcemon_sources, :team_id, :bigint
    add_index :sourcemon_sources, :team_id
  end
end
```

## How ModelExtensions Works Internally

### Registration (`ModelExtensions.register`)

Called by each engine model during class loading:

```ruby
# In SourceMonitor::Source (simplified)
SourceMonitor::ModelExtensions.register(self, :source)
```

This:
1. Looks up the `ModelDefinition` for the given key
2. Sets `table_name` based on `table_name_prefix + base_table`
3. Includes all registered concerns (deduped by signature)
4. Applies all registered validations

### Reload (`ModelExtensions.reload!`)

Called by `SourceMonitor.configure` after the block runs. Re-applies all extensions to all registered models. Safe to call multiple times.

### Concern Deduplication

Concerns are tracked by signature:
- Named module: `[:module, object_id]`
- String constant: `[:constant, "MyApp::SourceExtensions"]`
- Anonymous block: `[:anonymous_module, block.object_id]`

### Validation Management

Extension validations are tracked separately from model-native validations. On reload:
1. Previous extension validations are removed
2. New extension validations are applied
3. Model-native validations are untouched

## Limitations and Gotchas

1. **Table name prefix is global** -- changing it affects all engine tables. Must match existing migration table names or you need to rename tables.

2. **Concern order matters** -- concerns are included in registration order. If concern B depends on an association from concern A, register A first.

3. **Anonymous blocks create new modules** -- each `configure` call with a block creates a new anonymous module. In development with code reloading, this is fine because `reload!` re-applies everything.

4. **Validations with symbols** require the method to exist on the model. Define it in a concern and register the concern before the validation.

5. **Foreign keys** -- when adding associations to engine models, use explicit `foreign_key` and `class_name` options to avoid namespace confusion.

6. **Engine table names** -- always reference tables by their prefixed name (e.g., `sourcemon_sources`), not the model name.

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/model_extensions.rb` | Registration, reload, apply logic |
| `lib/source_monitor/configuration/models.rb` | Models config with MODEL_KEYS |
| `lib/source_monitor/configuration/model_definition.rb` | Per-model concern + validation storage |
| `lib/source_monitor/configuration/validation_definition.rb` | Validation wrapper |
| `lib/source_monitor.rb` | `configure` and `reset_configuration!` |

## References

- `reference/extension-api.md` -- Detailed API reference
- `docs/configuration.md` -- Configuration documentation (Model Extensions section)

## Testing

```ruby
require "test_helper"

module TestExtensions
  extend ActiveSupport::Concern

  included do
    scope :test_scope, -> { where.not(url: nil) }
  end

  def test_method
    "extended"
  end
end

class ModelExtensionTest < ActiveSupport::TestCase
  setup do
    SourceMonitor.reset_configuration!
  end

  test "include_concern adds methods to source" do
    SourceMonitor.configure do |config|
      config.models.source.include_concern TestExtensions
    end

    source = create_source!
    assert_equal "extended", source.test_method
    assert_respond_to SourceMonitor::Source, :test_scope
  end

  test "validate adds custom validation" do
    SourceMonitor.configure do |config|
      config.models.source.validate ->(record) {
        record.errors.add(:base, "test error")
      }
    end

    source = SourceMonitor::Source.new
    source.valid?
    assert_includes source.errors[:base], "test error"
  end

  test "table_name_prefix changes table names" do
    SourceMonitor.configure do |config|
      config.models.table_name_prefix = "custom_"
    end
    SourceMonitor::ModelExtensions.reload!

    assert_equal "custom_sources", SourceMonitor::Source.table_name
  end
end
```

## Checklist

- [ ] Extension concern defined under `app/models/concerns/`
- [ ] Concern registered via `config.models.<model>.include_concern`
- [ ] Custom validations registered via `config.models.<model>.validate`
- [ ] Foreign keys use explicit `foreign_key:` option
- [ ] Host migration created for any new columns on engine tables
- [ ] Tests verify extension behavior
- [ ] Tests use `SourceMonitor.reset_configuration!` in setup
- [ ] Extension is idempotent (safe to apply multiple times)
