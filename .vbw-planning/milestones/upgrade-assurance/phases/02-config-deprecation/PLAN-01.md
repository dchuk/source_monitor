---
phase: 2
plan: "01"
title: config-deprecation-framework
type: execute
wave: 1
depends_on: []
cross_phase_deps: [{phase: 1, plan: "01", artifact: "lib/source_monitor.rb", reason: "Autoload declarations pattern established in Phase 1"}]
autonomous: true
effort_override: thorough
skills_used: [sm-configuration-setting, sm-engine-test]
files_modified:
  - lib/source_monitor/configuration/deprecation_registry.rb
  - lib/source_monitor.rb
  - lib/source_monitor/configuration.rb
  - test/lib/source_monitor/configuration/deprecation_registry_test.rb
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/deprecation_registry_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/configuration/deprecation_registry.rb` exits 0 with no offenses"
    - "Running `bin/rails test` exits 0 with 992+ runs and 0 failures"
    - "Running `bin/rubocop` exits 0 with no offenses"
    - "SourceMonitor.configure with only valid current options produces zero deprecation warnings"
  artifacts:
    - path: "lib/source_monitor/configuration/deprecation_registry.rb"
      provides: "Deprecation registry that stores entries and checks config for deprecated option usage (REQ-28)"
      contains: "class DeprecationRegistry"
    - path: "lib/source_monitor/configuration.rb"
      provides: "Configuration#check_deprecations! called from SourceMonitor.configure"
      contains: "check_deprecations!"
    - path: "lib/source_monitor.rb"
      provides: "SourceMonitor.configure calls check_deprecations! after yielding config block"
      contains: "check_deprecations!"
    - path: "test/lib/source_monitor/configuration/deprecation_registry_test.rb"
      provides: "Tests covering all DeprecationRegistry branches including warning, error, no-op, and DSL"
      contains: "class DeprecationRegistryTest"
  key_links:
    - from: "deprecation_registry.rb"
      to: "REQ-28"
      via: "Stores deprecation entries and checks config object for stale/renamed/removed options"
    - from: "configuration.rb#check_deprecations!"
      to: "deprecation_registry.rb"
      via: "Configuration delegates deprecation checking to the registry"
    - from: "source_monitor.rb#configure"
      to: "configuration.rb#check_deprecations!"
      via: "configure method triggers deprecation check after block completes"
---
<objective>
Build a lightweight configuration deprecation framework (REQ-28) that warns host app developers when their initializer uses config options that have been renamed or removed. The framework provides a DeprecationRegistry DSL for engine developers to register deprecations, hooks into SourceMonitor.configure to scan after the config block completes, and produces actionable Rails.logger.warn messages for :warning severity or raises SourceMonitor::DeprecatedOptionError for :error severity. No real deprecations exist today -- the framework is infrastructure for future use, validated with synthetic test deprecations.
</objective>
<context>
@lib/source_monitor/configuration.rb -- Main configuration class. Has attr_accessor for top-level options (queue_namespace, fetch_queue_name, etc.) and attr_reader for nested settings objects (http, scrapers, retention, events, models, realtime, fetching, health, authentication, scraping, images). The check_deprecations! method will be added here, delegating to DeprecationRegistry.check!(self). Key: deprecation paths use dot notation matching this structure -- e.g. "queue_namespace" for top-level, "http.timeout" for nested.

@lib/source_monitor/configuration/http_settings.rb -- Example settings class pattern. Plain Ruby class with attr_accessor and reset!. Shows the structure that deprecation checking must traverse: each settings class is a separate object accessible via config.http, config.fetching, etc. The registry needs to resolve dot-notation paths by splitting on "." and walking the config object graph.

@lib/source_monitor/configuration/fetching_settings.rb -- Another settings class showing the pattern: initialize calls reset!, attr_accessor for all fields. The deprecation framework does NOT modify these classes. It inspects them from outside by calling respond_to? and public_send.

@lib/source_monitor/configuration/retention_settings.rb -- Settings class with custom setters (strategy=). Shows that some settings use custom writer methods rather than raw attr_accessor. The deprecation framework checks if an option was SET, not just if it exists. Approach: the registry stores the old option path and checks if the config object responds to that method. For renamed options, it checks if the old method exists (it should not on current config -- if it does, someone is calling it). For removed options, if someone references a method that no longer exists, Ruby will raise NoMethodError before our check runs. So the practical approach is: register deprecations with the OLD path, and during check!, attempt to resolve the path. If the path resolves (meaning the old option still exists as an accessor), log the warning. If it does not resolve, skip silently (the option was already removed, and any access would have raised NoMethodError naturally). For `:error` severity removed options, we use a different approach: install a method_missing trap or explicitly define a method that raises.

**Simpler design decision:** The registry operates in two modes:
1. **Renamed options** (severity: :warning): The old option path still exists as an alias or the registry defines a getter that warns and delegates. But this adds complexity. Simpler: just scan a "deprecation log" that tracks which deprecated setters were called.
2. **Post-configure scan** (chosen approach): After the configure block runs, iterate all registered deprecations and check if the deprecated option was accessed. Since we cannot easily detect "was this setter called" without wrapping it, the simplest approach is:
   - For :warning (renamed): Register a `method_missing` or `define_method` on the relevant settings class that logs a warning and forwards to the new option.
   - For :error (removed): Register a `define_method` on the relevant settings class that raises.
   - Alternative: Use a tracking hash. When register is called, we dynamically define a setter on the settings class that records the access in the registry, then the post-configure check reports all recorded accesses.

**Final design (simplest):** The DeprecationRegistry stores entries. When an entry is registered, it dynamically defines a method on the target settings class (or Configuration itself for top-level options) that:
- For :warning -- logs via Rails.logger.warn, then forwards to the replacement option
- For :error -- raises SourceMonitor::DeprecatedOptionError with the migration message
This is clean because: (a) the method is defined once at registration time, (b) it fires when the host app actually calls the deprecated setter in their configure block, (c) no post-scan needed, (d) zero overhead for non-deprecated options.

The `register` DSL: `DeprecationRegistry.register("http.proxy_url", removed_in: "0.5.0", replacement: "http.proxy", severity: :warning, message: "Use config.http.proxy instead")`. The registry parses the path, finds the settings class, and defines the trapping method.

For testing, we register synthetic deprecations (e.g. a fake option "http.old_timeout") and verify that accessing it in a configure block triggers the warning/error.

@lib/source_monitor.rb lines 197-217 -- The `configure` method yields config, then calls ModelExtensions.reload!. The deprecation framework hooks in here. Since we chose the define_method approach (methods fire on access, not post-scan), the configure method does NOT need a post-scan call. However, adding `config.check_deprecations!` as a post-configure hook is still useful as a safety net and for "removed option" detection. Actually, with the define_method approach, removed options raise immediately when accessed. So the only role for check_deprecations! is belt-and-suspenders. We can keep it simple: register defines methods, no post-scan needed. But for completeness and the "zero false positives" criterion, add a `check_deprecations!` that the configure method calls. This method iterates all :error entries and verifies the config is clean (no-op if no errors were raised, which is guaranteed by the define_method traps). Actually, let's just keep the define_method approach and skip the post-scan entirely. The `configure` method stays unchanged. The registry is self-contained.

**Revised final design:** DeprecationRegistry is a class with class-level state (entries hash). `register` stores the entry and defines a method on the target class. `clear!` removes all registered deprecations and undefines the methods (for test isolation). `entries` returns the hash for inspection. No changes to `SourceMonitor.configure` needed -- the trapping methods fire during the configure block naturally. Add `check_deprecations!` to Configuration anyway for explicit post-configure validation (iterates entries, no-op for now, but extensible for future "default changed" checks).

@test/lib/source_monitor/configuration_test.rb -- Existing configuration tests with setup/teardown that calls reset_configuration!. The deprecation registry test file follows the same pattern but also clears the registry in teardown. Tests use synthetic deprecations registered in setup, then verify warning/error behavior.

@lib/source_monitor/configuration/scraping_settings.rb -- Shows custom setter pattern (normalize_numeric). If a deprecated option path targets a class that already has a custom setter, the registry-defined method must coexist. Since we define a NEW method (the old/deprecated name), there is no collision with existing methods.
</context>
<tasks>
<task type="auto">
  <name>create-deprecation-registry</name>
  <files>
    lib/source_monitor/configuration/deprecation_registry.rb
  </files>
  <action>
Create `lib/source_monitor/configuration/deprecation_registry.rb` with the DeprecationRegistry class.

Module nesting: `SourceMonitor::Configuration::DeprecationRegistry`.

Class-level state (use class instance variables, not class variables):
- `@entries` -- Hash mapping `"path"` to entry hash `{ path:, removed_in:, replacement:, severity:, message: }`
- `@defined_methods` -- Array of `[klass, method_name]` tuples for cleanup

Class methods:

**`register(path, removed_in:, replacement: nil, severity: :warning, message: nil)`**
1. Parse `path` -- split on ".". If one segment, target class is `Configuration`. If two segments, first is the settings accessor name, second is the deprecated option name.
2. Resolve target class: for "http.old_option", the target is `Configuration::HTTPSettings`. Use a mapping hash: `{ "http" => HTTPSettings, "fetching" => FetchingSettings, "health" => HealthSettings, "scraping" => ScrapingSettings, "retention" => RetentionSettings, "realtime" => RealtimeSettings, "authentication" => AuthenticationSettings, "images" => ImagesSettings, "scraper" => ScraperRegistry, "events" => Events, "models" => Models }`. For top-level, target is `Configuration`.
3. Build the deprecation message: `"[SourceMonitor] DEPRECATION: '#{path}' was deprecated in v#{removed_in}#{replacement_text}. #{message}"`. Where replacement_text is ` and replaced by '#{replacement}'` if replacement is present.
4. Define a writer method (`"#{option_name}="`) on the target class:
   - For `:warning` severity: the method logs via `Rails.logger.warn(deprecation_message)` and, if replacement is present, forwards the value to the replacement setter. If no replacement, the value is silently dropped.
   - For `:error` severity: the method raises `SourceMonitor::DeprecatedOptionError.new(deprecation_message)`.
5. Also define a reader method (`option_name`) for :warning that forwards to replacement getter, or for :error that raises.
6. Store the entry in `@entries` and record `[target_class, method_name]` in `@defined_methods`.

**`clear!`**
Remove all defined methods from their target classes (use `remove_method`), clear `@entries` and `@defined_methods`. This is essential for test isolation.

**`entries`** -- returns `@entries.dup`

**`registered?(path)`** -- returns boolean

Also define `SourceMonitor::DeprecatedOptionError < StandardError` in this file.

Key design points:
- The SETTINGS_CLASSES mapping resolves settings accessor names to their Ruby classes.
- `define_method` is used on the target class so the trap fires during normal configure block usage.
- `remove_method` (not `undef_method`) is used in clear! so the class reverts to its original behavior.
- Thread safety: registration happens at boot time (in an initializer or engine config), not at runtime. No mutex needed.
- If the target class already responds to the deprecated method name, skip defining (the option is not actually removed/renamed yet -- this is a configuration error by the engine developer). Log a warning to stderr instead.
  </action>
  <verify>
Read the created file. Confirm: (a) class is SourceMonitor::Configuration::DeprecationRegistry, (b) register method accepts path/removed_in/replacement/severity/message, (c) define_method on target class for both reader and writer, (d) :warning severity logs and forwards, (e) :error severity raises DeprecatedOptionError, (f) clear! removes defined methods and resets state, (g) SETTINGS_CLASSES mapping covers all 11 settings classes, (h) DeprecatedOptionError is defined. Run `bin/rubocop lib/source_monitor/configuration/deprecation_registry.rb` -- 0 offenses.
  </verify>
  <done>
DeprecationRegistry class created with register/clear!/entries/registered? class methods. Defines trapping methods on target settings classes for both :warning and :error severities. DeprecatedOptionError defined. SETTINGS_CLASSES maps all 11 settings accessor names.
  </done>
</task>
<task type="auto">
  <name>wire-registry-into-configuration-and-autoload</name>
  <files>
    lib/source_monitor/configuration.rb
    lib/source_monitor.rb
  </files>
  <action>
**Modify `lib/source_monitor/configuration.rb`:**

Add a require at the top (after the existing requires, before the module definition):
```ruby
require "source_monitor/configuration/deprecation_registry"
```

Add a public method to Configuration:
```ruby
def check_deprecations!
  DeprecationRegistry.check_defaults!(self)
end
```

This method is a hook point for future "default changed" checks. For now, DeprecationRegistry.check_defaults! is a no-op class method (define it in the registry). It exists so that future phases can add checks like "option X changed its default from A to B in version Y".

**Modify `lib/source_monitor.rb`:**

In the `configure` method (around line 198), add `config.check_deprecations!` after `yield config` and before `ModelExtensions.reload!`:

```ruby
def configure
  yield config
  config.check_deprecations!
  SourceMonitor::ModelExtensions.reload!
end
```

Also in the `reset_configuration!` method, add `DeprecationRegistry.clear!` call to ensure test isolation works when resetting config:

Actually, NO -- `clear!` should NOT be called on reset_configuration. The registry is global engine state (deprecations are registered once at boot), not per-configuration-instance state. Clearing on reset would break the deprecation framework. Instead, test isolation for registry tests should call `DeprecationRegistry.clear!` in their own teardown.

So the only change to `reset_configuration!` is: nothing. Leave it as-is.

Summary of changes:
1. `configuration.rb`: Add `require` for deprecation_registry, add `check_deprecations!` method
2. `source_monitor.rb`: Add `config.check_deprecations!` in `configure` method after yield
  </action>
  <verify>
Read `lib/source_monitor/configuration.rb` -- confirm `require "source_monitor/configuration/deprecation_registry"` is present and `check_deprecations!` method exists. Read `lib/source_monitor.rb` -- confirm `config.check_deprecations!` is called in `configure` after yield. Run `bin/rubocop lib/source_monitor/configuration.rb lib/source_monitor.rb` -- 0 offenses.
  </verify>
  <done>
DeprecationRegistry required from configuration.rb. check_deprecations! method added to Configuration class. SourceMonitor.configure calls check_deprecations! after yield. No changes to reset_configuration! (registry state is global, not per-instance).
  </done>
</task>
<task type="auto">
  <name>create-deprecation-registry-tests</name>
  <files>
    test/lib/source_monitor/configuration/deprecation_registry_test.rb
  </files>
  <action>
Create `test/lib/source_monitor/configuration/deprecation_registry_test.rb` with comprehensive tests for the deprecation framework.

Module nesting: `SourceMonitor::Configuration::DeprecationRegistryTest < ActiveSupport::TestCase`.

Setup/teardown:
```ruby
setup do
  SourceMonitor.reset_configuration!
  DeprecationRegistry.clear!
end

teardown do
  DeprecationRegistry.clear!
  SourceMonitor.reset_configuration!
end
```

Tests to write (10 tests covering all branches):

1. **"register stores entry in registry"** -- Register a synthetic deprecation `"http.old_proxy_url"`. Assert `DeprecationRegistry.registered?("http.old_proxy_url")` is true. Assert `DeprecationRegistry.entries` has one entry with correct attributes.

2. **"warning severity logs deprecation and forwards to replacement"** -- Register `"http.old_proxy_url"` with severity: :warning, replacement: "http.proxy", removed_in: "0.5.0". Use a mock or string IO to capture Rails.logger.warn output. Call `SourceMonitor.configure { |c| c.http.old_proxy_url = "socks5://localhost" }`. Assert the warning message was logged (contains "DEPRECATION", "old_proxy_url", "0.5.0", "http.proxy"). Assert `SourceMonitor.config.http.proxy` equals "socks5://localhost" (forwarded).

3. **"warning severity reader forwards to replacement getter"** -- After registering and setting via the deprecated writer (as in test 2), read `config.http.old_proxy_url` and assert it returns the same value as `config.http.proxy`.

4. **"error severity raises DeprecatedOptionError on write"** -- Register `"http.removed_option"` with severity: :error, removed_in: "0.5.0", message: "This option was removed. Use X instead." Assert that `SourceMonitor.configure { |c| c.http.removed_option = "value" }` raises `SourceMonitor::DeprecatedOptionError` with message containing "removed_option" and "0.5.0".

5. **"error severity raises DeprecatedOptionError on read"** -- Register same as test 4. Assert that calling `SourceMonitor.config.http.removed_option` raises `SourceMonitor::DeprecatedOptionError`.

6. **"clear removes defined methods and entries"** -- Register a deprecation. Assert registered. Call `clear!`. Assert NOT registered. Assert `entries` is empty. Assert `SourceMonitor.config.http` does NOT respond_to the deprecated method name.

7. **"top-level option deprecation works"** -- Register `"old_queue_prefix"` (no dot -- targets Configuration directly) with severity: :warning, replacement: "queue_namespace". Configure with `config.old_queue_prefix = "my_app"`. Assert warning logged. Assert `config.queue_namespace` equals "my_app".

8. **"no warnings for valid current configuration"** (zero false positives criterion) -- Register a deprecation for a synthetic option. Then configure using ONLY valid current options (e.g. `config.http.timeout = 30`). Assert NO deprecation warnings were logged.

9. **"multiple deprecations can coexist"** -- Register two deprecations on different settings classes. Trigger both in one configure block. Assert both warnings logged.

10. **"check_deprecations! is called during configure"** -- Use a mock to verify that `check_deprecations!` is called. This validates the wiring from task 2.

For capturing Rails.logger.warn output, use:
```ruby
log_output = StringIO.new
original_logger = Rails.logger
Rails.logger = ActiveSupport::Logger.new(log_output)
# ... run configure ...
Rails.logger = original_logger
assert_match(/DEPRECATION/, log_output.string)
```

All 10 tests should pass. RuboCop clean.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/deprecation_registry_test.rb` -- all 10 tests pass with 0 failures. Run `bin/rubocop test/lib/source_monitor/configuration/deprecation_registry_test.rb` -- 0 offenses.
  </verify>
  <done>
10 tests pass covering: registration, warning with forwarding, warning reader, error on write, error on read, clear cleanup, top-level option, zero false positives, multiple coexistence, and configure wiring. RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>full-suite-verification-and-brakeman</name>
  <files>
  </files>
  <action>
Run the full verification suite to confirm no regressions and all quality gates pass.

1. `bin/rails test` -- full test suite passes with 992+ runs, 0 failures (the 10 new deprecation tests + existing 992)
2. `bin/rubocop` -- 0 offenses across all files
3. `bin/brakeman --no-pager` -- 0 warnings

If any failures:
- Test failures: read the failure output, identify the root cause, fix in the appropriate file
- RuboCop offenses: fix style issues in the offending files
- Brakeman warnings: evaluate and fix security concerns

After all gates pass, confirm:
- `grep -rn 'class DeprecationRegistry' lib/` returns the registry file
- `grep -rn 'check_deprecations!' lib/source_monitor/configuration.rb` returns the method
- `grep -rn 'check_deprecations!' lib/source_monitor.rb` returns the configure hook
- `grep -rn 'DeprecatedOptionError' lib/` returns the error class definition
- The existing configuration_test.rb still passes (reset_configuration! does not interfere with registry)
  </action>
  <verify>
`bin/rails test` exits 0 with 1002+ runs, 0 failures. `bin/rubocop` exits 0. `bin/brakeman --no-pager` exits 0. All grep checks return matches.
  </verify>
  <done>
Full suite green with 1002+ runs. RuboCop clean. Brakeman clean. All Phase 2 success criteria met. REQ-28 implemented: deprecation registry with DSL, boot-time warnings for :warning severity, errors for :error severity, zero false positives on current valid config.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/deprecation_registry_test.rb` -- 10 tests pass
2. `bin/rails test` -- 1002+ runs, 0 failures
3. `bin/rubocop` -- 0 offenses
4. `bin/brakeman --no-pager` -- 0 warnings
5. `grep -n 'class DeprecationRegistry' lib/source_monitor/configuration/deprecation_registry.rb` returns a match
6. `grep -n 'class DeprecatedOptionError' lib/source_monitor/configuration/deprecation_registry.rb` returns a match
7. `grep -n 'check_deprecations!' lib/source_monitor/configuration.rb` returns a match
8. `grep -n 'check_deprecations!' lib/source_monitor.rb` returns a match
9. `grep -n 'DeprecationRegistry' lib/source_monitor/configuration.rb` returns a match (require)
10. Existing `test/lib/source_monitor/configuration_test.rb` passes without modification
</verification>
<success_criteria>
- Engine maintains a deprecation registry with option path, version deprecated, replacement, and severity (REQ-28)
- At configuration load time, deprecated option usage triggers Rails.logger.warn with actionable message (REQ-28)
- Removed options that are still referenced raise DeprecatedOptionError with migration path (REQ-28)
- Framework is opt-in via simple DSL: DeprecationRegistry.register(path, removed_in:, ...) (REQ-28)
- Zero false positives on current valid configuration -- only synthetic test deprecations trigger warnings (REQ-28)
- bin/rails test passes with 1002+ runs, RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/02-config-deprecation/PLAN-01-SUMMARY.md
</output>
