# Debugger Memory

## Rails Association Cache Pollution Pattern
- `source.items.new` AND `Item.new(source: source)` both add to the loaded association cache via inverse_of
- Only `Item.new(source_id: source.id)` truly bypasses inverse_of and avoids cache pollution
- When unsaved/invalid records are in a loaded has_many cache, `parent.update!` triggers auto-save and fails with `RecordInvalid: Items is invalid`
- `update_columns` bypasses all callbacks and auto-save, safe to use with polluted caches
- After `update_columns`, call `reload` so the in-memory object reflects DB state

## Test Patterns
- Use `clean_source_monitor_tables!` in setup for blank-slate DB
- `create_source!` is the factory helper (in test_helper.rb)
- WebMock stubs + VCR cassettes for HTTP; `stub_request(:get, url)`
- Stub class methods with `singleton_class.define_method` pattern
- Always restore stubs in `ensure` block
