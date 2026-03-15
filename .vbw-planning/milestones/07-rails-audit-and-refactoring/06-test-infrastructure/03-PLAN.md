---
phase: 6
plan: 03
title: Sub-Module Unit Tests & Shared Concern Tests
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-engine-test, sm-domain-model, sm-architecture, tdd-cycle]
files_modified:
  - test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb
  - test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb
  - test/support/shared_loggable_tests.rb
  - test/models/source_monitor/fetch_log_test.rb
  - test/models/source_monitor/scrape_log_test.rb
  - test/models/source_monitor/health_check_log_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "AdaptiveInterval has dedicated unit tests covering interval calculation edge cases"
    - "SourceUpdater has dedicated unit tests covering source state mutations and log creation"
    - "Loggable concern behavior is tested via shared module included in 3 model test files"
  artifacts:
    - {path: "test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb", provides: "AdaptiveInterval unit tests", contains: "AdaptiveIntervalTest"}
    - {path: "test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb", provides: "SourceUpdater unit tests", contains: "SourceUpdaterTest"}
    - {path: "test/support/shared_loggable_tests.rb", provides: "Shared Loggable concern tests", contains: "SharedLoggableTests"}
  key_links:
    - {from: "test/support/shared_loggable_tests.rb", to: "test/models/source_monitor/fetch_log_test.rb", via: "include"}
---
<objective>
Create isolated unit tests for the extracted FeedFetcher sub-modules (AdaptiveInterval, SourceUpdater) that were refactored in Phase 3 but never got dedicated test files (T3). Also create a SharedLoggableTests module that tests the Loggable concern contract across FetchLog, ScrapeLog, and HealthCheckLog (T15). These fill the biggest unit test coverage gaps identified in the audit.
</objective>
<context>
@.claude/skills/sm-engine-test/SKILL.md -- test patterns, WebMock, factory helpers
@.claude/skills/sm-architecture/SKILL.md -- module tree, FeedFetcher sub-modules
@.claude/skills/sm-domain-model/SKILL.md -- model relationships, Loggable concern
@.claude/skills/tdd-cycle/SKILL.md -- TDD red-green-refactor cycle
</context>
<tasks>
<task type="auto">
  <name>Create AdaptiveInterval unit tests</name>
  <files>
    test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb
    lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb
  </files>
  <action>
Read lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb to understand the public interface.
Create test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb with tests covering:
1. Interval increases when no new items found (decay case)
2. Interval decreases when many new items found (active source case)
3. Interval respects min/max bounds from configuration
4. Interval stays unchanged when item count matches expected rate
5. Edge case: zero items, first fetch (no history)
6. Edge case: adaptive_fetching_enabled = false (no change)

Use create_source! with appropriate attributes. Test the module's public method(s) directly, not through FeedFetcher integration.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb -- all tests pass
  </verify>
  <done>
adaptive_interval_test.rb has 5+ tests covering interval calculation, bounds, and edge cases
  </done>
</task>
<task type="auto">
  <name>Create SourceUpdater unit tests</name>
  <files>
    test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb
    lib/source_monitor/fetching/feed_fetcher/source_updater.rb
  </files>
  <action>
Read lib/source_monitor/fetching/feed_fetcher/source_updater.rb to understand the public interface.
Create test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb with tests covering:
1. update_source_for_success -- resets failure_count, clears last_error, sets last_fetched_at, updates next_fetch_at
2. update_source_for_success -- updates etag/last_modified from response headers
3. update_source_for_failure -- increments failure_count, sets last_error and last_error_at
4. create_fetch_log -- creates FetchLog record with correct attributes (duration, status, items_found)
5. Edge case: source already in failed state, successful fetch resets it

Use create_source! with specific attributes. Stub external dependencies (HTTP, Feedjira) if SourceUpdater calls them -- but it likely operates on already-parsed data.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb -- all tests pass
  </verify>
  <done>
source_updater_test.rb has 5+ tests covering success/failure updates, log creation, and edge cases
  </done>
</task>
<task type="auto">
  <name>Create SharedLoggableTests module</name>
  <files>
    test/support/shared_loggable_tests.rb
  </files>
  <action>
Create test/support/shared_loggable_tests.rb with a SharedLoggableTests module (using ActiveSupport::Concern or plain module with `def self.included(base)`) that defines shared tests for the Loggable concern:
1. Test validates presence of started_at
2. Test validates duration_ms >= 0 (if present)
3. Test metadata defaults to empty hash
4. Test .recent scope returns records ordered by started_at DESC
5. Test .successful scope filters on success status
6. Test .failed scope filters on failure status

The including test class must define a `build_loggable(overrides = {})` method that returns an unsaved instance of the concrete model (FetchLog, ScrapeLog, or HealthCheckLog).
  </action>
  <verify>
ruby -c test/support/shared_loggable_tests.rb (syntax valid)
  </verify>
  <done>
SharedLoggableTests module exists with 5+ shared test methods for Loggable concern contract
  </done>
</task>
<task type="auto">
  <name>Include SharedLoggableTests in log model tests</name>
  <files>
    test/models/source_monitor/fetch_log_test.rb
    test/models/source_monitor/scrape_log_test.rb
    test/models/source_monitor/health_check_log_test.rb
  </files>
  <action>
For each log model test file (create if missing):
1. Require "support/shared_loggable_tests" (relative to test dir)
2. Include SharedLoggableTests in the test class
3. Define `build_loggable(overrides = {})` that returns an unsaved instance of the specific model with valid defaults (e.g., FetchLog.new(source: create_source!, started_at: Time.current))
4. Add any model-specific tests that are NOT covered by the shared module

If the test file doesn't exist yet (likely for some log models), create it with the standard Minitest structure:
```ruby
require "test_helper"
require_relative "../../../support/shared_loggable_tests"

module SourceMonitor
  class FetchLogTest < ActiveSupport::TestCase
    include SharedLoggableTests
    # ...
  end
end
```
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/fetch_log_test.rb test/models/source_monitor/scrape_log_test.rb test/models/source_monitor/health_check_log_test.rb -- all pass
  </verify>
  <done>
Three log model test files include SharedLoggableTests and pass. Loggable concern contract is validated across all 3 concrete implementations.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes (existing + new tests)
2. PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/adaptive_interval_test.rb -- passes
3. PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/source_updater_test.rb -- passes
4. PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/fetch_log_test.rb -- passes with SharedLoggableTests
5. New test count: 15+ new tests across 5 new/updated files
</verification>
<success_criteria>
- AdaptiveInterval has dedicated unit tests with 5+ test cases covering calculations, bounds, and edge cases
- SourceUpdater has dedicated unit tests with 5+ test cases covering success/failure updates and log creation
- SharedLoggableTests module validates Loggable concern contract (validations, scopes, defaults)
- All 3 log model test files include and pass SharedLoggableTests
- Full test suite passes with zero regressions
</success_criteria>
<output>
03-SUMMARY.md
</output>
