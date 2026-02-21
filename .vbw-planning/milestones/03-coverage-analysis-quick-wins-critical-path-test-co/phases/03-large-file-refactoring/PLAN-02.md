---
phase: 3
plan: 2
title: extract-configuration-settings
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `wc -l lib/source_monitor/configuration.rb` shows fewer than 120 lines"
    - "Running `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0 with zero failures"
    - "Running `bin/rails test` exits 0 with no regressions (760+ runs, 0 failures)"
    - "Running `ls lib/source_monitor/configuration/` shows at least 10 .rb files"
    - "Running `ruby -c lib/source_monitor/configuration.rb` exits 0"
    - "Running `grep -c 'class.*Settings\\|class.*Registry\\|class.*Events\\|class.*Models\\|class.*Definition' lib/source_monitor/configuration.rb` shows 0 (all nested classes extracted)"
  artifacts:
    - "lib/source_monitor/configuration/http_settings.rb"
    - "lib/source_monitor/configuration/fetching_settings.rb"
    - "lib/source_monitor/configuration/health_settings.rb"
    - "lib/source_monitor/configuration/realtime_settings.rb (includes SolidCableOptions)"
    - "lib/source_monitor/configuration/scraping_settings.rb"
    - "lib/source_monitor/configuration/retention_settings.rb"
    - "lib/source_monitor/configuration/scraper_registry.rb"
    - "lib/source_monitor/configuration/events.rb"
    - "lib/source_monitor/configuration/models.rb"
    - "lib/source_monitor/configuration/model_definition.rb (includes ConcernDefinition)"
    - "lib/source_monitor/configuration/validation_definition.rb"
    - "lib/source_monitor/configuration/authentication_settings.rb (includes Handler)"
    - "lib/source_monitor/configuration.rb -- slimmed to container class under 120 lines"
  key_links:
    - "REQ-09 satisfied -- Configuration nested classes extracted into separate files"
    - "Public API unchanged -- SourceMonitor.configure { |c| c.http.timeout = 30 } still works"
---

# Plan 02: extract-configuration-settings

## Objective

Extract the 12 nested classes from `lib/source_monitor/configuration.rb` (655 lines) into individual files under `lib/source_monitor/configuration/`. Each nested class (HTTPSettings, FetchingSettings, HealthSettings, RealtimeSettings + SolidCableOptions, ScrapingSettings, RetentionSettings, ScraperRegistry, Events, Models, ModelDefinition + ConcernDefinition, ValidationDefinition, AuthenticationSettings + Handler) becomes its own file. The main `configuration.rb` retains only the `Configuration` class shell with constructor, `queue_name_for`, `concurrency_for`, attr_accessors, and attr_readers. The public API (`SourceMonitor.configure { |c| ... }`) remains unchanged.

## Context

<context>
@lib/source_monitor/configuration.rb -- 655 lines. Contains Configuration class with ~70 lines of its own logic, plus 12 nested classes totaling ~585 lines. Each nested class is already well-encapsulated with its own initialize, reset!, and domain-specific methods.
@test/lib/source_monitor/configuration_test.rb -- 860 lines of tests covering all settings classes. MUST NOT be modified.
@lib/source_monitor.rb -- line 41: `require "source_monitor/configuration"`. New sub-files will be required from configuration.rb itself.

**Decomposition rationale:** The Configuration file is large solely because it contains 12 independently testable classes. Unlike FeedFetcher (which requires careful method delegation), this extraction is mechanical: move each class to its own file, add require statements, and verify. The classes have no circular dependencies between them -- they're all leaf nodes of the Configuration tree.

**Trade-offs considered:**
- Could keep small classes (like FetchingSettings at 20 lines) inline and only extract large ones. But consistency is more valuable than saving a few files, and the target is under 300 lines total.
- Could use autoload instead of require. Deferring to Plan 04 (REQ-12) which handles autoloading holistically.
- SolidCableOptions is nested inside RealtimeSettings. Keep them in the same file (`realtime_settings.rb`) since SolidCableOptions is only used by RealtimeSettings.
- ConcernDefinition is nested inside ModelDefinition. Keep them in the same file (`model_definition.rb`).
- Handler is nested inside AuthenticationSettings. Keep them in the same file (`authentication_settings.rb`).

**What constrains the structure:**
- Nested class names must remain accessible as `Configuration::HTTPSettings`, `Configuration::Events`, etc.
- All requires go in configuration.rb before the class body
- Tests reference these classes via `SourceMonitor::Configuration::EventsClass` or through `SourceMonitor.config.events` -- both patterns must continue working
- `frozen_string_literal: true` pragma on all new files
</context>

## Tasks

### Task 1: Extract settings classes (HTTP, Fetching, Health, Scraping)

- **name:** extract-basic-settings
- **files:**
  - `lib/source_monitor/configuration/http_settings.rb` (new)
  - `lib/source_monitor/configuration/fetching_settings.rb` (new)
  - `lib/source_monitor/configuration/health_settings.rb` (new)
  - `lib/source_monitor/configuration/scraping_settings.rb` (new)
  - `lib/source_monitor/configuration.rb`
- **action:** Create `lib/source_monitor/configuration/` directory. For each of the four settings classes (HTTPSettings lines 256-292, FetchingSettings lines 294-314, HealthSettings lines 316-336, ScrapingSettings lines 132-164), create a new file with the class defined as `SourceMonitor::Configuration::ClassName`. Each file gets `frozen_string_literal: true`. Add require statements at the top of configuration.rb: `require "source_monitor/configuration/http_settings"` etc. Remove the class bodies from configuration.rb. Verify the class is still accessible as `SourceMonitor::Configuration::HTTPSettings`.
- **verify:** `ruby -c lib/source_monitor/configuration/http_settings.rb lib/source_monitor/configuration/fetching_settings.rb lib/source_monitor/configuration/health_settings.rb lib/source_monitor/configuration/scraping_settings.rb` exits 0 AND `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0
- **done:** Four simple settings classes extracted. Tests pass.

### Task 2: Extract complex settings classes (Realtime, Retention, Authentication)

- **name:** extract-complex-settings
- **files:**
  - `lib/source_monitor/configuration/realtime_settings.rb` (new, includes SolidCableOptions)
  - `lib/source_monitor/configuration/retention_settings.rb` (new)
  - `lib/source_monitor/configuration/authentication_settings.rb` (new, includes Handler struct)
  - `lib/source_monitor/configuration.rb`
- **action:** Extract RealtimeSettings (lines 166-254, includes SolidCableOptions inner class), RetentionSettings (lines 398-436), and AuthenticationSettings (lines 75-130, includes Handler Struct). Keep SolidCableOptions nested inside RealtimeSettings in the same file. Keep Handler nested inside AuthenticationSettings in the same file. Add require statements to configuration.rb. Remove class bodies from configuration.rb.
- **verify:** `ruby -c lib/source_monitor/configuration/realtime_settings.rb lib/source_monitor/configuration/retention_settings.rb lib/source_monitor/configuration/authentication_settings.rb` exits 0 AND `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0
- **done:** Three complex settings classes extracted with their inner classes. Tests pass.

### Task 3: Extract registry, events, models, and definition classes

- **name:** extract-registry-events-models
- **files:**
  - `lib/source_monitor/configuration/scraper_registry.rb` (new)
  - `lib/source_monitor/configuration/events.rb` (new)
  - `lib/source_monitor/configuration/models.rb` (new)
  - `lib/source_monitor/configuration/model_definition.rb` (new, includes ConcernDefinition)
  - `lib/source_monitor/configuration/validation_definition.rb` (new)
  - `lib/source_monitor/configuration.rb`
- **action:** Extract ScraperRegistry (lines 338-396), Events (lines 438-491), Models (lines 493-522), ModelDefinition (lines 524-625, includes ConcernDefinition inner class), and ValidationDefinition (lines 627-652). Keep ConcernDefinition nested inside ModelDefinition. Add require statements to configuration.rb. Remove all remaining nested class bodies from configuration.rb. The main configuration.rb should now contain only: require statements, the Configuration class with attr_accessor/attr_reader declarations, initialize (instantiating all settings objects), queue_name_for, and concurrency_for.
- **verify:** `ruby -c lib/source_monitor/configuration/scraper_registry.rb lib/source_monitor/configuration/events.rb lib/source_monitor/configuration/models.rb lib/source_monitor/configuration/model_definition.rb lib/source_monitor/configuration/validation_definition.rb` exits 0 AND `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0 AND `wc -l lib/source_monitor/configuration.rb` shows fewer than 120 lines
- **done:** All nested classes extracted. Configuration.rb under 120 lines. Full configuration test suite passes.

### Task 4: Verify line counts and full suite

- **name:** verify-extraction-complete
- **files:**
  - `lib/source_monitor/configuration.rb`
  - `lib/source_monitor/configuration/*.rb`
- **action:** Run `wc -l` on all extracted files and the main configuration.rb. Verify no extracted file exceeds 300 lines. Verify the main file is under 120 lines. Run `bin/rubocop lib/source_monitor/configuration.rb lib/source_monitor/configuration/` to verify style compliance. Run `bin/rails test` for the full suite. Fix any RuboCop issues (likely just the frozen_string_literal pragma which should already be present).
- **verify:** `wc -l lib/source_monitor/configuration.rb` shows fewer than 120 lines AND no file in `lib/source_monitor/configuration/` exceeds 300 lines AND `bin/rails test` exits 0 with 760+ runs AND `bin/rubocop lib/source_monitor/configuration.rb lib/source_monitor/configuration/` exits 0
- **done:** Configuration extraction complete. All files under limits. Full suite passes. RuboCop clean.

## Verification

1. `wc -l lib/source_monitor/configuration.rb` shows fewer than 120 lines
2. `ls lib/source_monitor/configuration/*.rb | wc -l` shows 12 files
3. `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0
4. `bin/rails test` exits 0 (no regressions)
5. `bin/rubocop lib/source_monitor/configuration.rb lib/source_monitor/configuration/` exits 0

## Success Criteria

- [ ] Configuration main file under 120 lines (down from 655)
- [ ] 12 extracted files in lib/source_monitor/configuration/
- [ ] No extracted file exceeds 300 lines
- [ ] Public API unchanged -- SourceMonitor.configure { |c| c.http.timeout = 30 } works
- [ ] All existing configuration tests pass without modification (860 lines)
- [ ] Full test suite passes (760+ runs, 0 failures)
- [ ] RuboCop passes on all modified/new files
- [ ] REQ-09 satisfied
