---
phase: 6
plan: 01
title: Centralize Factory Helpers
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-engine-test, tdd-cycle]
files_modified:
  - test/support/model_factories.rb
  - test/test_helper.rb
  - test/lib/source_monitor/items/retention_pruner_test.rb
  - test/lib/source_monitor/scraping/enqueuer_test.rb
  - test/lib/source_monitor/scraping/state_test.rb
  - test/lib/source_monitor/scraping/scheduler_test.rb
  - test/lib/source_monitor/scraping/bulk_source_scraper_test.rb
  - test/lib/source_monitor/realtime/broadcaster_test.rb
  - test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb
  - test/lib/source_monitor/health/source_health_monitor_test.rb
  - test/lib/source_monitor/items/item_creator_test.rb
  - test/lib/source_monitor/events/event_system_test.rb
  - test/lib/source_monitor/scraping/item_scraper/adapter_resolver_test.rb
  - test/jobs/source_monitor/download_content_images_job_test.rb
  - test/jobs/source_monitor/scrape_item_job_test.rb
  - test/jobs/source_monitor/log_cleanup_job_test.rb
  - test/jobs/source_monitor/item_cleanup_job_test.rb
  - test/controllers/source_monitor/source_scrape_tests_controller_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "All existing tests pass after factory consolidation"
    - "No test file defines its own create_item or build_source helper"
  artifacts:
    - {path: "test/support/model_factories.rb", provides: "Shared factory module", contains: "module ModelFactories"}
    - {path: "test/test_helper.rb", provides: "Factory module inclusion", contains: "model_factories"}
  key_links:
    - {from: "test/support/model_factories.rb", to: "test/test_helper.rb", via: "require + include"}
---
<objective>
Create a shared ModelFactories module in test/support/model_factories.rb that consolidates duplicated factory helpers (create_item, build_source, create_fetch_log, create_scrape_log, create_log_entry, create_health_check_log) from 12+ test files into a single reusable module. The existing create_source! helper stays in test_helper.rb. The new module is required and included in test_helper.rb so all tests get it automatically. Then audit and update all test files that define local copies to use the shared versions instead. (T6)
</objective>
<context>
@.claude/skills/sm-engine-test/SKILL.md -- test helper conventions, create_source! pattern
@.claude/skills/tdd-cycle/SKILL.md -- TDD workflow, Minitest conventions
</context>
<tasks>
<task type="auto">
  <name>Create ModelFactories module</name>
  <files>
    test/support/model_factories.rb
  </files>
  <action>
Create test/support/model_factories.rb with a ModelFactories module containing:
- `create_item!(source:, **overrides)` -- creates SourceMonitor::Item with sensible defaults (guid, url, title, published_at). Uses SecureRandom.hex for unique guid/url. Returns persisted record.
- `create_fetch_log!(source:, **overrides)` -- creates SourceMonitor::FetchLog with defaults (started_at, status, duration_ms).
- `create_scrape_log!(item:, source: nil, **overrides)` -- creates SourceMonitor::ScrapeLog, auto-derives source from item if not given.
- `create_health_check_log!(source:, **overrides)` -- creates SourceMonitor::HealthCheckLog with defaults.
- `create_log_entry!(source:, loggable:, **overrides)` -- creates SourceMonitor::LogEntry.
- `create_item_content!(item:, **overrides)` -- creates SourceMonitor::ItemContent with defaults.

Each helper follows the create_source! pattern: set defaults, merge overrides, save! (with validate: false where appropriate for test speed). Use SecureRandom.hex for uniqueness in guid/url fields.
  </action>
  <verify>
ruby -c test/support/model_factories.rb (syntax check passes)
  </verify>
  <done>
test/support/model_factories.rb exists with all 6 factory methods defined in a module
  </done>
</task>
<task type="auto">
  <name>Wire factories into test_helper</name>
  <files>
    test/test_helper.rb
  </files>
  <action>
Add `require_relative "support/model_factories"` near top of test/test_helper.rb (after existing requires).
Add `include ModelFactories` inside the ActiveSupport::TestCase class reopening (alongside existing create_source!).
Move create_source! INTO the ModelFactories module as well (keep backward compat -- it will still be available via include). Update test_helper.rb to no longer define create_source! directly -- the module now provides it.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb -- passes (create_source! still works)
  </verify>
  <done>
test_helper.rb requires and includes ModelFactories module; create_source! is defined in the module
  </done>
</task>
<task type="auto">
  <name>Migrate test files to shared factories</name>
  <files>
    test/lib/source_monitor/items/retention_pruner_test.rb
    test/lib/source_monitor/scraping/enqueuer_test.rb
    test/lib/source_monitor/scraping/state_test.rb
    test/lib/source_monitor/scraping/scheduler_test.rb
    test/lib/source_monitor/scraping/bulk_source_scraper_test.rb
    test/lib/source_monitor/realtime/broadcaster_test.rb
    test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb
    test/lib/source_monitor/health/source_health_monitor_test.rb
    test/lib/source_monitor/items/item_creator_test.rb
    test/lib/source_monitor/events/event_system_test.rb
    test/lib/source_monitor/scraping/item_scraper/adapter_resolver_test.rb
    test/jobs/source_monitor/download_content_images_job_test.rb
    test/jobs/source_monitor/scrape_item_job_test.rb
    test/jobs/source_monitor/log_cleanup_job_test.rb
    test/jobs/source_monitor/item_cleanup_job_test.rb
    test/controllers/source_monitor/source_scrape_tests_controller_test.rb
  </files>
  <action>
For each test file that defines its own create_item, build_source, create_fetch_log, create_scrape_log, or create_health_check_log:
1. Remove the local helper method definition
2. Update call sites to match the shared factory's signature (e.g., create_item! with keyword args)
3. If local helper has custom defaults that differ from the shared factory, pass overrides at the call site

Note: Some test files may have unique factory variants (e.g., create_item with extra fields). Preserve those as local helpers only if they add genuinely unique test-specific logic. Otherwise migrate to the shared version with overrides.
  </action>
  <verify>
bin/rails test -- full suite passes with zero failures
  </verify>
  <done>
No test file outside test/support/ defines create_item, build_source, create_fetch_log, create_scrape_log, or create_health_check_log. grep -r "def create_item\b\|def build_source\b\|def create_fetch_log\b\|def create_scrape_log\b\|def create_health_check" test/ returns only test/support/model_factories.rb
  </done>
</task>
<task type="auto">
  <name>Verify and document</name>
  <files>
    test/support/model_factories.rb
  </files>
  <action>
1. Run full test suite to confirm zero regressions
2. Add a comment block at the top of model_factories.rb documenting each factory's signature, defaults, and usage examples
3. Verify no test file still uses direct Model.create! for common models (Item, FetchLog, ScrapeLog) -- these should use the factory helpers. Flag any remaining direct calls but do not change them if they are intentionally testing model validations.
  </action>
  <verify>
bin/rails test -- all tests pass
grep -r "def create_item\b\|def build_source" test/ --include="*.rb" | grep -v model_factories returns no matches
  </verify>
  <done>
All tests pass. Factory module is documented. No duplicate factory definitions remain outside the shared module.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes (1214+ tests, 0 failures)
2. grep -r "def create_item" test/ returns only test/support/model_factories.rb
3. grep -r "def build_source" test/ returns only test/support/model_factories.rb (or no matches if consolidated into create_source!)
4. grep -r "def create_fetch_log" test/ returns only test/support/model_factories.rb
5. ruby -c test/support/model_factories.rb -- syntax valid
</verification>
<success_criteria>
- test/support/model_factories.rb exists with create_item!, create_fetch_log!, create_scrape_log!, create_health_check_log!, create_log_entry!, create_item_content! helpers
- test/test_helper.rb requires and includes ModelFactories
- No test file outside test/support/ defines its own create_item, build_source, create_fetch_log, or create_scrape_log
- Full test suite passes with zero regressions
</success_criteria>
<output>
01-SUMMARY.md
</output>
