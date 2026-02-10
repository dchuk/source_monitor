---
phase: 2
plan: 3
title: configuration-tests
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0 with zero failures"
    - "Coverage report shows lib/source_monitor/configuration.rb has fewer than 20 uncovered lines (down from 94)"
    - "Running `bin/rails test` exits 0 with no regressions"
  artifacts:
    - "test/lib/source_monitor/configuration_test.rb -- extended with new test methods covering AuthenticationSettings, ScrapingSettings, RealtimeSettings, RetentionSettings, Events, Models, and ModelDefinition"
  key_links:
    - "REQ-03 substantially satisfied -- Configuration branch coverage above 80%"
---

# Plan 03: configuration-tests

## Objective

Close the coverage gap in `lib/source_monitor/configuration.rb` (currently 94 uncovered lines out of 655). The existing test file has only 5 tests covering mission_control_dashboard_path, scraper registry, retention strategy default, and fetching settings. This plan targets the remaining uncovered branches across the 12 nested settings classes: AuthenticationSettings handlers, ScrapingSettings normalization, RealtimeSettings adapter validation and action_cable_config, RetentionSettings strategy validation, Events callbacks and item_processors, Models table_name_prefix and `for` method, ModelDefinition concerns and validations, ConcernDefinition resolution, and ValidationDefinition signatures.

## Context

<context>
@lib/source_monitor/configuration.rb -- 655 lines with ~12 nested classes
@test/lib/source_monitor/configuration_test.rb -- existing test file with 5 tests
@config/coverage_baseline.json -- lists 94 uncovered lines for configuration.rb
@test/test_helper.rb -- resets configuration each test

**Decomposition rationale:** Configuration has many small nested classes, each with a few uncovered branches. Rather than one mega-task, we group by logical subsystem: (1) authentication handlers, (2) scraping/retention settings with edge cases, (3) realtime adapter validation, (4) events system, (5) models and concern/validation definitions.

**Trade-offs considered:**
- Could create separate test files per settings class, but the existing pattern is one configuration_test.rb file.
- Some branches (like ConcernDefinition with constant string resolution) require careful setup to test constantize calls.
- RealtimeSettings action_cable_config branches test all three adapter paths.

**What constrains the structure:**
- Each test must call SourceMonitor.reset_configuration! in setup/teardown (already present)
- Tests should not leak state between settings classes
- ModelDefinition tests need care around Module.new blocks
</context>

## Tasks

### Task 1: Test AuthenticationSettings handlers

- **name:** test-authentication-settings
- **files:**
  - `test/lib/source_monitor/configuration_test.rb`
- **action:** Add tests covering lines 75-130 (AuthenticationSettings and Handler). Specifically:
  1. Test authenticate_with(:some_method) creates a Handler with type :symbol that calls controller.public_send (lines 80-82)
  2. Test authenticate_with { |c| c.redirect_to "/" } creates a Handler with type :callable that calls the block with controller (lines 84-88) -- test both zero-arity and one-arity blocks
  3. Test authorize_with works the same way (line 105-107)
  4. Test that passing an invalid handler (not Symbol, String, or callable) raises ArgumentError (line 127)
  5. Test reset! clears all handlers and methods (lines 109-114)
  6. Test Handler.call returns nil when callable is nil (line 78)
  Use a mock controller object (OpenStruct with method stubs) to verify handler dispatch.
- **verify:** `bin/rails test test/lib/source_monitor/configuration_test.rb -n /authentication|authorize|handler/i` exits 0
- **done:** Lines 75-130 covered.

### Task 2: Test ScrapingSettings and RetentionSettings edge cases

- **name:** test-scraping-and-retention-settings
- **files:**
  - `test/lib/source_monitor/configuration_test.rb`
- **action:** Add tests covering lines 132-164 (ScrapingSettings) and lines 398-436 (RetentionSettings). Specifically:
  1. Test ScrapingSettings defaults (max_in_flight_per_source=25, max_bulk_batch_size=100)
  2. Test ScrapingSettings normalize_numeric: nil returns nil, "" returns nil, negative returns nil, positive returns integer (lines 157-163)
  3. Test ScrapingSettings setter with string input (e.g., "50") normalizes to integer
  4. Test RetentionSettings strategy= with nil defaults to :destroy (line 419)
  5. Test RetentionSettings strategy= with invalid value raises ArgumentError (line 430)
  6. Test RetentionSettings strategy= with string "soft_delete" normalizes to symbol
  7. Test RetentionSettings strategy= with non-symbolizable value raises ArgumentError (line 433)
- **verify:** `bin/rails test test/lib/source_monitor/configuration_test.rb -n /scraping_settings|retention_settings|normalize/i` exits 0
- **done:** Lines 132-164 and 398-436 covered.

### Task 3: Test RealtimeSettings adapter validation and action_cable_config

- **name:** test-realtime-settings
- **files:**
  - `test/lib/source_monitor/configuration_test.rb`
- **action:** Add tests covering lines 166-253 (RealtimeSettings, SolidCableOptions). Specifically:
  1. Test adapter= with :solid_cable, :redis, :async all accepted (line 178)
  2. Test adapter= with :invalid raises ArgumentError (line 179)
  3. Test action_cable_config for :solid_cable returns hash with adapter: "solid_cable" and SolidCableOptions merged (lines 197-198)
  4. Test action_cable_config for :redis returns hash with adapter: "redis" and redis_url when set (lines 200-202)
  5. Test action_cable_config for :async returns { adapter: "async" } (line 204)
  6. Test SolidCableOptions.assign with a hash of options sets the corresponding attributes (lines 223-229)
  7. Test SolidCableOptions.to_h compacts nil values (line 251)
  8. Test solid_cable= delegates to solid_cable.assign (line 192)
- **verify:** `bin/rails test test/lib/source_monitor/configuration_test.rb -n /realtime|adapter|action_cable|solid_cable/i` exits 0
- **done:** Lines 166-253 covered.

### Task 4: Test Events callbacks and item_processors

- **name:** test-events-system
- **files:**
  - `test/lib/source_monitor/configuration_test.rb`
- **action:** Add tests covering lines 438-491 (Events). Specifically:
  1. Test registering after_item_created callback with a lambda and retrieving via callbacks_for(:after_item_created) (lines 446-449)
  2. Test registering after_item_created callback with a block
  3. Test register_item_processor adds to item_processors list (lines 452-457)
  4. Test that passing non-callable to register_item_processor raises ArgumentError (line 488)
  5. Test that registering unknown event key raises ArgumentError (line 479)
  6. Test callbacks_for returns empty array for unregistered name (line 460)
  7. Test reset! clears all callbacks and item_processors (lines 467-470)
- **verify:** `bin/rails test test/lib/source_monitor/configuration_test.rb -n /events|callback|item_processor/i` exits 0
- **done:** Lines 438-491 covered.

### Task 5: Test Models, ModelDefinition, ConcernDefinition, and ValidationDefinition

- **name:** test-models-and-definitions
- **files:**
  - `test/lib/source_monitor/configuration_test.rb`
- **action:** Add tests covering lines 493-652 (Models, ModelDefinition, ConcernDefinition, ValidationDefinition). Specifically:
  1. Test Models.table_name_prefix default is "sourcemon_" (line 507)
  2. Test Models.for(:source) returns a ModelDefinition, and Models.for(:unknown) raises ArgumentError (lines 515-521)
  3. Test ModelDefinition.include_concern with a Module directly (line 591-592)
  4. Test ModelDefinition.include_concern with a string constant name that resolves (lines 593-598)
  5. Test ModelDefinition.include_concern with a block creates anonymous module (lines 588-590)
  6. Test ModelDefinition.include_concern deduplicates by signature (line 534)
  7. Test ModelDefinition.validate with symbol, with callable (proc), and with block (lines 549-563)
  8. Test ModelDefinition.validate with invalid handler raises ArgumentError (line 558)
  9. Test ValidationDefinition.signature for symbol, callable, and string handlers (lines 636-647)
  10. Test ValidationDefinition.symbol? (lines 649-651)
  Use real module references and string constants for concern resolution tests.
- **verify:** `bin/rails test test/lib/source_monitor/configuration_test.rb -n /models|model_definition|concern|validation_definition/i` exits 0
- **done:** Lines 493-652 covered.

## Verification

1. `bin/rails test test/lib/source_monitor/configuration_test.rb` exits 0
2. `COVERAGE=1 bin/rails test test/lib/source_monitor/configuration_test.rb` shows configuration.rb with >80% branch coverage
3. `bin/rails test` exits 0 (no regressions)

## Success Criteria

- [ ] Configuration coverage drops from 94 uncovered lines to fewer than 20
- [ ] AuthenticationSettings handlers fully tested
- [ ] ScrapingSettings and RetentionSettings edge cases tested
- [ ] RealtimeSettings adapter validation and action_cable_config tested
- [ ] Events callbacks and item_processors tested
- [ ] Models and definition classes tested
- [ ] REQ-03 substantially satisfied
