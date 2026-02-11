# Model Extension API Reference

Detailed reference for extending SourceMonitor engine models from host applications.

Source: `lib/source_monitor/model_extensions.rb`, `lib/source_monitor/configuration/models.rb`, `lib/source_monitor/configuration/model_definition.rb`

## Configuration API

### `config.models`

Class: `SourceMonitor::Configuration::Models`

#### `table_name_prefix`

| Property | Type | Default |
|---|---|---|
| `table_name_prefix` | String | `"sourcemon_"` |

Changes the database table name prefix for all engine models.

```ruby
config.models.table_name_prefix = "sm_"
# sourcemon_sources -> sm_sources
# sourcemon_items -> sm_items
# etc.
```

#### Model Accessors

Each returns a `ModelDefinition` instance:

| Accessor | Key | Engine Model |
|---|---|---|
| `config.models.source` | `:source` | `SourceMonitor::Source` |
| `config.models.item` | `:item` | `SourceMonitor::Item` |
| `config.models.fetch_log` | `:fetch_log` | `SourceMonitor::FetchLog` |
| `config.models.scrape_log` | `:scrape_log` | `SourceMonitor::ScrapeLog` |
| `config.models.health_check_log` | `:health_check_log` | `SourceMonitor::HealthCheckLog` |
| `config.models.item_content` | `:item_content` | `SourceMonitor::ItemContent` |
| `config.models.log_entry` | `:log_entry` | `SourceMonitor::LogEntry` |

#### `for(name) -> ModelDefinition`

Look up a model definition by key. Raises `ArgumentError` for unknown models.

---

## ModelDefinition API

Class: `SourceMonitor::Configuration::ModelDefinition`

### `include_concern(concern = nil, &block)`

Include a concern module into the engine model.

**Three forms:**

```ruby
# 1. String constant (lazy -- recommended for autoloaded classes)
config.models.source.include_concern "MyApp::SourceExtension"

# 2. Module reference (immediate)
config.models.source.include_concern MyApp::SourceExtension

# 3. Anonymous block
config.models.source.include_concern do
  has_many :tags, dependent: :destroy
  scope :tagged, ->(t) { joins(:tags).where(tags: { name: t }) }
end
```

**Deduplication:** Concerns are deduplicated by signature:

| Form | Signature |
|---|---|
| String | `[:constant, "MyApp::SourceExtension"]` |
| Module | `[:module, <object_id>]` |
| Block | `[:anonymous_module, <block_object_id>]` |

Including the same concern twice (by signature) is a no-op.

**Return value:**
- String: returns the string
- Module: returns the module
- Block: returns the anonymous module created from the block

### `validate(handler = nil, **options, &block)`

Register a validation on the engine model.

**Forms:**

```ruby
# 1. Symbol -- method name (must exist on the model, typically from a concern)
config.models.source.validate :check_custom_rules

# 2. Callable (proc/lambda)
config.models.source.validate ->(record) {
  record.errors.add(:url, "must use HTTPS") unless record.url&.start_with?("https://")
}

# 3. Block
config.models.source.validate do |record|
  record.errors.add(:base, "invalid") unless record.valid_for_host?
end

# With options (passed to ActiveModel::Validations.validate)
config.models.source.validate :check_limits, on: :create
config.models.source.validate :check_format, if: :needs_format_check?
```

**Returns:** A `ValidationDefinition` instance.

### `validations -> Array<ValidationDefinition>`

Read-only list of registered validations.

### `each_concern { |signature, module| }`

Iterate over registered concerns. Yields signature and resolved module.

---

## ValidationDefinition

Class: `SourceMonitor::Configuration::ValidationDefinition`

| Method | Returns | Description |
|---|---|---|
| `handler` | Symbol/Proc | The validation handler |
| `options` | Hash | Options passed to `validate` (e.g., `on:`, `if:`) |
| `signature` | Array | Unique identifier for deduplication |
| `symbol?` | Boolean | True if handler is a Symbol or String |

---

## ModelExtensions Module

Class: `SourceMonitor::ModelExtensions`

### `register(model_class, key)`

Called by each engine model during class loading to register itself:

```ruby
# Inside SourceMonitor::Source (simplified)
SourceMonitor::ModelExtensions.register(self, :source)
```

Actions:
1. Adds the model to the internal registry
2. Sets `table_name` using `table_name_prefix + base_table`
3. Includes all registered concerns (via `apply_concerns`)
4. Applies all registered validations (via `apply_validations`)

### `reload!`

Re-applies all extensions to all registered models. Called by:
- `SourceMonitor.configure` (after the block runs)
- `SourceMonitor.reset_configuration!`

Safe to call multiple times. Idempotent for concerns (deduplicated). Validations are removed and re-applied on each reload.

---

## Internal Mechanics

### Table Name Assignment

```ruby
def assign_table_name(entry)
  desired = "#{SourceMonitor.table_name_prefix}#{entry.base_table}"
  model_class.table_name = desired
end
```

`base_table` is derived from the model class name: `Source` -> `sources`, `FetchLog` -> `fetch_logs`.

### Concern Application

```ruby
def apply_concerns(model_class, definition)
  applied = model_class.instance_variable_get(:@_source_monitor_extension_concerns) || []

  definition.each_concern do |signature, mod|
    next if applied.include?(signature)
    model_class.include(mod) unless model_class < mod
    applied << signature
  end

  model_class.instance_variable_set(:@_source_monitor_extension_concerns, applied)
end
```

Concerns are tracked via an instance variable on the model class. Including the same module twice is prevented both by signature tracking and the `model_class < mod` check.

### Validation Application

```ruby
def apply_validations(model_class, definition)
  remove_extension_validations(model_class)  # Remove previous extensions

  definition.validations.each do |validation|
    if validation.symbol?
      model_class.validate(validation.handler, **validation.options)
    else
      callback = proc { |record| validation.handler.call(record) }
      model_class.validate(**validation.options, &callback)
    end
  end
end
```

Extension validations are tracked separately. On reload:
1. Previous extension validations are removed from `_validate_callbacks`
2. New validations are applied fresh
3. Model-native validations are never touched

---

## Concern Definition Internals

Class: `SourceMonitor::Configuration::ModelDefinition::ConcernDefinition` (private)

### Resolver

| Form | Behavior |
|---|---|
| Block | Creates `Module.new(&block)`, wraps in lazy resolver |
| Module | Returns the module directly |
| String | Calls `constantize` lazily (raises `ArgumentError` on `NameError`) |

### Lazy Resolution

String-based concerns are not constantized until `resolve` is called. This allows registering concerns for classes that haven't been loaded yet (common with autoloading).

---

## Patterns and Examples

### Adding Associations

```ruby
# app/models/concerns/my_app/source_monitor/source_extensions.rb
module MyApp::SourceMonitor::SourceExtensions
  extend ActiveSupport::Concern

  included do
    has_many :source_tags,
      class_name: "MyApp::SourceTag",
      foreign_key: :sourcemon_source_id,
      dependent: :destroy

    has_many :tags, through: :source_tags, class_name: "MyApp::Tag"
  end
end
```

### Adding Scopes

```ruby
config.models.source.include_concern do
  scope :active_in_team, ->(team_id) {
    where(team_id: team_id).where.not(paused_at: nil)
  }

  scope :with_recent_items, -> {
    where(id: SourceMonitor::Item.where("created_at > ?", 24.hours.ago).select(:source_id))
  }
end
```

### Adding Callbacks

```ruby
config.models.item.include_concern do
  after_create :update_source_item_count

  private

  def update_source_item_count
    source.update_column(:items_count, source.items.count)
  end
end
```

### Multi-Model Extensions

```ruby
SourceMonitor.configure do |config|
  # Extend sources
  config.models.source.include_concern "MyApp::SourceMonitor::SourceExtensions"
  config.models.source.validate :validate_team_assignment

  # Extend items
  config.models.item.include_concern "MyApp::SourceMonitor::ItemExtensions"
  config.models.item.validate ->(record) {
    record.errors.add(:title, "too short") if record.title&.length.to_i < 5
  }

  # Extend fetch logs
  config.models.fetch_log.include_concern do
    scope :for_team, ->(team_id) {
      joins(:source).where(sourcemon_sources: { team_id: team_id })
    }
  end
end
```

### Custom Table Prefix

```ruby
config.models.table_name_prefix = "feeds_"
# Tables: feeds_sources, feeds_items, feeds_fetch_logs, etc.
```

Requires matching migration table names. If changing prefix on an existing install, you must rename tables.
