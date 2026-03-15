---
phase: 6
plan: 04
title: Mocking Standardization & Test Conventions Guide
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: balanced
skills_used: [sm-engine-test, tdd-cycle]
files_modified:
  - test/TEST_CONVENTIONS.md
  - test/lib/source_monitor/fetching/advisory_lock_test.rb
  - test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb
forbidden_commands: []
must_haves:
  truths:
    - "Test conventions are documented with mocking approach, naming style, and job testing patterns"
    - "Advisory lock test uses Minitest stub instead of Class.new anonymous mocking"
    - "All existing tests still pass after mock refactoring"
  artifacts:
    - {path: "test/TEST_CONVENTIONS.md", provides: "Test conventions documentation", contains: "Mocking"}
  key_links: []
---
<objective>
Standardize the mocking approach across the test suite by documenting conventions and refactoring the most egregious cases of Class.new anonymous mocking to use Minitest's .stub pattern. Create a TEST_CONVENTIONS.md guide covering mocking, naming, job testing, and WebMock stub patterns so contributors follow consistent practices. (T7, T8, T12, T14)
</objective>
<context>
@.claude/skills/sm-engine-test/SKILL.md -- existing test patterns, WebMock/VCR usage
@.claude/skills/tdd-cycle/SKILL.md -- Minitest conventions
</context>
<tasks>
<task type="auto">
  <name>Create TEST_CONVENTIONS.md</name>
  <files>
    test/TEST_CONVENTIONS.md
  </files>
  <action>
Create test/TEST_CONVENTIONS.md documenting:

**1. Mocking Approach** (T7)
- Primary: Use Minitest `.stub` for all mocking needs
- When to use `Object.stub(:method, return_value) { block }` -- method stubs on existing objects/classes
- When anonymous Class.new is acceptable: ONLY when you need a full duck-type object implementing multiple methods (rare)
- Avoid: Mocha, rspec-mocks, or other external mocking libraries
- Examples of good and bad patterns

**2. Test Naming** (T14)
- Convention: Start with action verb in present tense (imperative mood)
- Format: "verb [condition] [expected outcome]"
- Good: "creates item from RSS entry", "raises error when feed URL is blank"
- Bad: "test that it works", "item creation"

**3. Job Testing** (T12)
- Default adapter is `:test` -- jobs are enqueued but not performed
- Use `assert_enqueued_with(job: JobClass)` to verify enqueueing
- Use `with_inline_jobs { }` when you need jobs to execute (integration/system tests)
- Use `with_queue_adapter(:async)` only for specific async behavior tests
- Rule of thumb: unit tests use `:test`, system/integration tests use `with_inline_jobs`

**4. WebMock Stub Patterns** (T8)
- Define reusable stub helpers in test-specific helper files for complex stubs
- Use `file_fixture` for response bodies (not inline strings)
- Naming: `stub_feed_request(url:, fixture:, status: 200)`
- Always stub ALL external requests a test might make -- WebMock will raise on unmatched requests

**5. Time Travel**
- Always use block form: `travel_to(time) { ... }` (auto travel_back)
- If block form not feasible, add `ensure travel_back` to the test method

**6. Test Isolation**
- Scope all queries to test-created records (never assert global counts)
- Use SecureRandom.hex for unique identifiers
- Call `SourceMonitor.reset_configuration!` is handled automatically in setup

Keep it concise (under 150 lines). Reference test/support/ modules and test_helper.rb for implementation details.
  </action>
  <verify>
test -f test/TEST_CONVENTIONS.md (file exists)
wc -l test/TEST_CONVENTIONS.md reports under 200 lines
  </verify>
  <done>
TEST_CONVENTIONS.md exists with sections on mocking, naming, job testing, WebMock stubs, time travel, and isolation
  </done>
</task>
<task type="auto">
  <name>Refactor advisory_lock_test mocking</name>
  <files>
    test/lib/source_monitor/fetching/advisory_lock_test.rb
  </files>
  <action>
Read the advisory_lock_test.rb file. Refactor Class.new anonymous mocking patterns to use Minitest .stub where feasible:
1. Replace `fake_connection = Class.new { def exec_query(sql)... end }.new` with a stub approach
2. If the fake_connection needs multiple methods, keep Class.new but add a comment explaining why .stub is insufficient
3. Ensure the connection_pool.stub pattern remains (it's correct Minitest usage)

Goal: demonstrate the preferred mocking pattern, not rewrite every mock in the codebase.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/advisory_lock_test.rb -- all tests pass
  </verify>
  <done>
advisory_lock_test.rb uses consistent mocking patterns with comments explaining the approach
  </done>
</task>
<task type="auto">
  <name>Consolidate feed_fetcher_test_helper stubs</name>
  <files>
    test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb
  </files>
  <action>
Read test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb.
1. Review existing shared stub helpers -- document them with comments if undocumented
2. Add any missing common stub helpers:
   - `stub_feed_request(url:, fixture: "feeds/rss_sample.xml", status: 200, headers: {})` -- if not already present
   - `stub_feed_timeout(url:)` -- stubs request to raise Faraday::TimeoutError
   - `stub_feed_not_found(url:)` -- stubs 404 response
3. Ensure helpers follow the documented mocking conventions from TEST_CONVENTIONS.md

This file is already a shared helper -- the goal is to improve it, not create a new one.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/ -- all fetching tests pass
  </verify>
  <done>
feed_fetcher_test_helper.rb has documented, reusable WebMock stub helpers following conventions
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes
2. test -f test/TEST_CONVENTIONS.md
3. grep "Mocking" test/TEST_CONVENTIONS.md returns matches
4. PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/advisory_lock_test.rb -- passes
</verification>
<success_criteria>
- test/TEST_CONVENTIONS.md documents mocking approach, test naming, job testing, WebMock patterns, time travel, and isolation
- advisory_lock_test.rb uses Minitest .stub consistently (or has comments explaining why Class.new is needed)
- feed_fetcher_test_helper.rb has documented reusable stub helpers
- All tests pass with zero regressions
</success_criteria>
<output>
04-SUMMARY.md
</output>
