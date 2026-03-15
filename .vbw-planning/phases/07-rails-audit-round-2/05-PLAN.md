---
phase: 7
plan: 05
title: Test Reliability & Codebase Cleanup
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-engine-test, sm-architecture, tdd-cycle, performance-optimization]
files_modified:
  - test/controllers/source_monitor/sources_controller_test.rb
  - test/controllers/source_monitor/fetch_logs_controller_test.rb
  - test/controllers/source_monitor/scrape_logs_controller_test.rb
  - test/test_helper.rb
  - lib/source_monitor/fetching/feed_fetcher.rb
  - lib/source_monitor/items/item_creator.rb
  - lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb
  - lib/source_monitor/images/downloader.rb
  - lib/source_monitor/fetching/cloudflare_bypass.rb
forbidden_commands: []
must_haves:
  truths:
    - "Pagination tests do not call Source.destroy_all or any global table truncation"
    - "Pagination test assertions scope to test-created records, not global counts"
    - "FetchLogsController and ScrapeLogsController have test files with basic CRUD coverage"
    - "FeedFetcher backward-compat forwarding methods have deprecation warnings or are removed"
    - "Swallowed exceptions in feed_fetcher.rb have Rails.logger.warn (M17 partial)"
  artifacts:
    - {path: "test/controllers/source_monitor/fetch_logs_controller_test.rb", provides: "FetchLogsController test coverage", contains: "class FetchLogsControllerTest"}
    - {path: "test/controllers/source_monitor/scrape_logs_controller_test.rb", provides: "ScrapeLogsController test coverage", contains: "class ScrapeLogsControllerTest"}
  key_links:
    - {from: "test/controllers/source_monitor/sources_controller_test.rb", to: "test/test_helper.rb", via: "Uses create_source! with scoped assertions"}
---
<objective>
Fix pagination test parallel-safety (H6), add missing test files for FetchLogsController, ScrapeLogsController, and ImportHistory model (L30), clean up backward-compat forwarding methods (L14), remove duplicated constants (L15), standardize Images::Downloader HTTP client usage (L17), add CloudflareBypass timeout safety (L19), and consolidate duplicated test helpers (L28).
</objective>
<context>
@.claude/skills/sm-engine-test/SKILL.md -- test isolation rules, parallel safety, factory helpers
@.claude/skills/sm-architecture/SKILL.md -- module tree, pipeline architecture
@.claude/skills/tdd-cycle/SKILL.md -- TDD workflow
@.claude/skills/performance-optimization/SKILL.md -- HTTP client patterns

Key context: 7 pagination tests in sources_controller_test.rb call Source.destroy_all for a clean slate, violating the project's own parallel-safety rules documented in TEST_CONVENTIONS.md. With thread-based parallelism, this races with other test threads. FetchLogsController and ScrapeLogsController have no test files. FeedFetcher has 12 forwarding methods and ItemCreator has 18 -- remnants from Phase 3/4 sub-module extraction.
</context>
<tasks>
<task type="auto">
  <name>Fix pagination test parallel-safety (H6)</name>
  <files>
    test/controllers/source_monitor/sources_controller_test.rb
  </files>
  <action>
1. Find all tests that call `Source.destroy_all` (approximately 7 tests around lines 252-322).
2. Replace the `destroy_all` approach with scoped assertions:
   - Create test sources with a unique naming pattern (e.g., `"PaginationTest-#{n}"`)
   - Instead of asserting global counts, assert that specific test-created records appear/don't appear in the response
   - Or: use `assert_select` to check for specific record content rather than counting total rows
3. Alternative approach: Create a separate test class `SourcesPaginationTest` that uses `clean_source_monitor_tables!` in setup (this is the documented safe approach for tests that need blank-slate counting).
4. Ensure assertions work correctly with thread-based parallelism -- other threads may create Source records concurrently.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/controllers/source_monitor/sources_controller_test.rb
bin/rails test -- full suite with parallelism passes
  </verify>
  <done>
No Source.destroy_all calls remain in pagination tests. Assertions are scoped to test-created records or use a properly isolated test class.
  </done>
</task>
<task type="auto">
  <name>Add missing controller test files (L30 partial)</name>
  <files>
    test/controllers/source_monitor/fetch_logs_controller_test.rb
    test/controllers/source_monitor/scrape_logs_controller_test.rb
  </files>
  <action>
1. Create test/controllers/source_monitor/fetch_logs_controller_test.rb with basic tests:
   - GET index returns 200
   - Index scopes to correct source if source_id param present
   - Renders log entries in the response
2. Create test/controllers/source_monitor/scrape_logs_controller_test.rb with similar basic coverage.

Note: ImportHistory model test is handled by Plan 01 (L12 task). Check existing routes to determine what actions these controllers support (likely just index/show). Use the engine's integration test patterns.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/controllers/source_monitor/fetch_logs_controller_test.rb test/controllers/source_monitor/scrape_logs_controller_test.rb
  </verify>
  <done>
Two new controller test files exist with basic coverage. All pass.
  </done>
</task>
<task type="auto">
  <name>Consolidate duplicated test helpers (L28)</name>
  <files>
    test/test_helper.rb
  </files>
  <action>
1. L28: Find the 4 test files that duplicate `configure_authentication` helper. Extract it to test_helper.rb or to test/support/ module.
2. Update the 4 files to remove local definitions and use the shared version.
3. Verify by grep that no duplicate definitions remain.
  </action>
  <verify>
grep -r "def configure_authentication" test/ returns only one definition in the shared location
  </verify>
  <done>
configure_authentication helper defined once in shared location, used by all test files that need it.
  </done>
</task>
<task type="auto">
  <name>Clean up forwarding methods, duplicated constants, and swallowed exceptions (L14, L15, M17 partial)</name>
  <files>
    lib/source_monitor/fetching/feed_fetcher.rb
    lib/source_monitor/items/item_creator.rb
    lib/source_monitor/fetching/feed_fetcher/adaptive_interval.rb
  </files>
  <action>
1. L14: In FeedFetcher (12 forwarding methods) and ItemCreator (18 forwarding methods), add deprecation warnings using `ActiveSupport::Deprecation.warn("FeedFetcher#method_name is deprecated, use SubModule#method_name instead", caller_locations(1))` or simply remove if no external callers exist. Check git blame to see if these were added in Phase 3/4 extraction -- if the extraction shipped months ago and no external code references these, they can be removed.
2. L15: In FeedFetcher, remove constants that are duplicated from AdaptiveInterval. Replace references with `AdaptiveInterval::CONSTANT_NAME`.
3. M17 (partial -- feed_fetcher.rb only): Find any `rescue StandardError => nil` or bare rescue blocks in feed_fetcher.rb and add `Rails.logger.warn("[SourceMonitor] Swallowed exception in FeedFetcher: #{e.class}: #{e.message}")`.
  </action>
  <verify>
bin/rails test test/lib/source_monitor/fetching/ test/lib/source_monitor/items/
  </verify>
  <done>
Forwarding methods removed or deprecated. Duplicated constants removed from FeedFetcher, referencing AdaptiveInterval instead.
  </done>
</task>
<task type="auto">
  <name>Minor pipeline fixes (L17, L19)</name>
  <files>
    lib/source_monitor/images/downloader.rb
    lib/source_monitor/fetching/cloudflare_bypass.rb
  </files>
  <action>
1. L17: In Images::Downloader, replace the raw `Faraday::Connection.new` with `SourceMonitor::HTTP.client` to use the centralized HTTP client factory. This ensures consistent timeout, SSL, and header configuration.
2. L19: In CloudflareBypass, the sequential 4-user-agent retry can take 60s+. Add a `max_attempts` parameter (default: 2) to limit retries. Add a per-request timeout that's shorter than the main fetch timeout to prevent accumulation.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/ test/lib/source_monitor/fetching/
  </verify>
  <done>
Images::Downloader uses HTTP.client. CloudflareBypass has attempt limit to prevent 60s+ fetches.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes with zero failures (including with parallelism)
2. bin/rubocop -- zero offenses on modified files
3. grep -r "destroy_all" test/controllers/source_monitor/sources_controller_test.rb returns no matches
4. grep -r "def configure_authentication" test/ returns only one shared definition
5. Test files exist: fetch_logs_controller_test.rb, scrape_logs_controller_test.rb
</verification>
<success_criteria>
- Pagination tests are parallel-safe, no destroy_all calls (H6)
- FetchLogsController, ScrapeLogsController, ImportHistory have test files (L30)
- configure_authentication helper consolidated (L28)
- FeedFetcher/ItemCreator forwarding methods cleaned up (L14)
- Duplicated constants removed from FeedFetcher (L15)
- Images::Downloader uses centralized HTTP client (L17)
- CloudflareBypass has attempt limit (L19)
- All tests pass with zero regressions
</success_criteria>
<output>
05-SUMMARY.md
</output>
