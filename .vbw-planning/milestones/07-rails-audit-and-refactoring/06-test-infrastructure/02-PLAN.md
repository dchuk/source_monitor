---
phase: 6
plan: 02
title: System Test Base Class & VCR Documentation
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-engine-test, tdd-cycle]
files_modified:
  - test/application_system_test_case.rb
  - test/support/system_test_helpers.rb
  - test/system/dashboard_test.rb
  - test/system/items_test.rb
  - test/system/logs_test.rb
  - test/system/sources_test.rb
  - test/system/mission_control_test.rb
  - test/system/dropdown_fallback_test.rb
  - test/VCR_GUIDE.md
forbidden_commands: []
must_haves:
  truths:
    - "All system tests pass after refactoring to use shared base class"
    - "Capybara default_max_wait_time is configured centrally (not per-assertion)"
    - "VCR cassette strategy is documented"
  artifacts:
    - {path: "test/application_system_test_case.rb", provides: "System test base class with wait config", contains: "default_max_wait_time"}
    - {path: "test/support/system_test_helpers.rb", provides: "Shared system test helpers", contains: "module SystemTestHelpers"}
    - {path: "test/VCR_GUIDE.md", provides: "VCR cassette maintenance documentation", contains: "cassette"}
  key_links:
    - {from: "test/support/system_test_helpers.rb", to: "test/application_system_test_case.rb", via: "include"}
---
<objective>
Enhance the existing ApplicationSystemTestCase with proper Capybara wait configuration, screenshot-on-failure, and temp file cleanup. Extract shared system test helpers (purge_solid_queue_tables, assert_item_order, etc.) from individual test files into a SystemTestHelpers module. Create VCR cassette maintenance documentation. (T1, T9, T16, T17)
</objective>
<context>
@.claude/skills/sm-engine-test/SKILL.md -- test infrastructure patterns
@.claude/skills/tdd-cycle/SKILL.md -- Minitest test conventions
</context>
<tasks>
<task type="auto">
  <name>Enhance ApplicationSystemTestCase</name>
  <files>
    test/application_system_test_case.rb
  </files>
  <action>
Update test/application_system_test_case.rb to add:
1. Capybara configuration: `Capybara.default_max_wait_time = 5` (centralize the scattered wait: 5 values)
2. Common setup: `SourceMonitor.reset_configuration!` and `SourceMonitor::Jobs::Visibility.reset!` / `setup!`
3. Teardown with cleanup: reset config, reset Jobs::Visibility, call `clean_test_tmp_files` (conditionally clean test/tmp/ artifacts older than 1 hour)
4. Screenshot on failure: override `after_teardown` to save screenshot if test failed (Capybara's built-in `take_failed_screenshot` if available)
5. Keep existing driven_by, ActionCable::TestHelper, Turbo::Broadcastable::TestHelper includes

Do NOT add `purge_solid_queue_tables` to base setup -- only dashboard tests need it. That goes in SystemTestHelpers as an opt-in method.
  </action>
  <verify>
ruby -c test/application_system_test_case.rb (syntax valid)
  </verify>
  <done>
ApplicationSystemTestCase has Capybara wait config, setup/teardown, screenshot-on-failure, and tmp cleanup
  </done>
</task>
<task type="auto">
  <name>Create SystemTestHelpers module</name>
  <files>
    test/support/system_test_helpers.rb
  </files>
  <action>
Create test/support/system_test_helpers.rb with a SystemTestHelpers module containing helpers extracted from system test files:
1. `purge_solid_queue_tables` -- from dashboard_test.rb (purges SolidQueue tables)
2. `seed_queue_activity(source:)` -- from dashboard_test.rb (seeds queue data for testing)
3. `apply_turbo_stream_messages(page)` -- from dashboard_test.rb (processes turbo stream messages in Capybara)
4. `parse_turbo_streams(html)` -- from dashboard_test.rb (parses turbo stream HTML)
5. `assert_item_order(expected_titles)` -- from items_test.rb (asserts item display order)

Include this module in ApplicationSystemTestCase via require_relative + include.
  </action>
  <verify>
ruby -c test/support/system_test_helpers.rb (syntax valid)
  </verify>
  <done>
SystemTestHelpers module exists with all extracted helpers, included in ApplicationSystemTestCase
  </done>
</task>
<task type="auto">
  <name>Refactor system tests to use shared base</name>
  <files>
    test/system/dashboard_test.rb
    test/system/items_test.rb
    test/system/logs_test.rb
    test/system/sources_test.rb
    test/system/mission_control_test.rb
    test/system/dropdown_fallback_test.rb
  </files>
  <action>
For each system test file:
1. Remove local setup/teardown logic now handled by ApplicationSystemTestCase (config reset, Jobs::Visibility reset/setup)
2. Remove local helper method definitions that are now in SystemTestHelpers (purge_solid_queue_tables, assert_item_order, etc.)
3. Keep test-specific setup that is NOT shared (e.g., dashboard_test still calls purge_solid_queue_tables in its own setup since not all system tests need it, but the METHOD is defined centrally)
4. Remove explicit `wait: 5` from assertions where Capybara's default_max_wait_time (now 5) handles it. Keep explicit waits only where they differ from default (e.g., wait: 10 for slow operations)
5. Verify each test file still requires "application_system_test_case"
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/system/ -- all system tests pass
  </verify>
  <done>
System test files use shared base class setup/teardown and SystemTestHelpers. No duplicated helper definitions across system test files.
  </done>
</task>
<task type="auto">
  <name>Create VCR cassette maintenance guide</name>
  <files>
    test/VCR_GUIDE.md
  </files>
  <action>
Create test/VCR_GUIDE.md documenting:
1. **Overview**: VCR is configured in test_helper.rb, hooks into WebMock, cassettes stored in test/vcr_cassettes/
2. **Naming convention**: `source_monitor/<domain>/<scenario>` (e.g., source_monitor/fetching/rss_success)
3. **When to use VCR vs WebMock stubs**: VCR for complex multi-request flows with real response bodies; WebMock stubs for simple single-request mocks where response content doesn't matter
4. **Recording new cassettes**: `VCR.use_cassette("name", record: :new_episodes) { ... }` then commit the YAML
5. **Regenerating stale cassettes**: Delete the YAML file, run the test with `record: :new_episodes`, review diff
6. **Current cassettes**: List the 4 existing cassettes and their purpose
7. **Maintenance**: Check cassettes annually or when upstream feed formats change; cassettes with expired SSL certs need re-recording
  </action>
  <verify>
test -f test/VCR_GUIDE.md (file exists)
  </verify>
  <done>
VCR_GUIDE.md exists with naming convention, recording strategy, regeneration guide, and cassette inventory
  </done>
</task>
</tasks>
<verification>
1. PARALLEL_WORKERS=1 bin/rails test test/system/ -- all system tests pass
2. bin/rails test -- full suite passes
3. grep -r "def purge_solid_queue_tables" test/ returns only test/support/system_test_helpers.rb (plus test/lib/ if that has its own copy for non-system tests)
4. grep "default_max_wait_time" test/application_system_test_case.rb returns a match
5. test -f test/VCR_GUIDE.md
</verification>
<success_criteria>
- ApplicationSystemTestCase has Capybara.default_max_wait_time = 5, screenshot-on-failure, and tmp cleanup
- SystemTestHelpers module centralizes shared helpers from system test files
- System test files no longer define their own copies of shared helpers
- test/VCR_GUIDE.md documents cassette naming, recording, and maintenance strategy
- All system tests pass without regressions
</success_criteria>
<output>
02-SUMMARY.md
</output>
