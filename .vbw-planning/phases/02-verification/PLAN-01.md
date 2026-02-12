---
phase: 2
plan: "01"
title: recurring-schedule-verifier
type: execute
wave: 1
depends_on: []
cross_phase_deps:
  - phase: 1
    artifact: "lib/source_monitor/setup/verification/solid_queue_verifier.rb"
    reason: "Phase 2 modifies this file's remediation message (REQ-20)"
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - lib/source_monitor/setup/verification/recurring_schedule_verifier.rb
  - lib/source_monitor/setup/verification/solid_queue_verifier.rb
  - lib/source_monitor/setup/verification/runner.rb
  - lib/source_monitor.rb
  - test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb
  - test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb
  - test/lib/source_monitor/setup/verification/runner_test.rb
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/setup/verification/recurring_schedule_verifier.rb lib/source_monitor/setup/verification/solid_queue_verifier.rb lib/source_monitor/setup/verification/runner.rb` exits 0 with no offenses"
    - "Running `bin/rails test` exits 0 with 867+ runs and 0 failures"
  artifacts:
    - path: "lib/source_monitor/setup/verification/recurring_schedule_verifier.rb"
      provides: "Verifier that checks SolidQueue recurring tasks registration (REQ-19)"
      contains: "class RecurringScheduleVerifier"
    - path: "lib/source_monitor/setup/verification/solid_queue_verifier.rb"
      provides: "Enhanced remediation mentioning Procfile.dev (REQ-20)"
      contains: "Procfile.dev"
    - path: "lib/source_monitor/setup/verification/runner.rb"
      provides: "Runner wires RecurringScheduleVerifier into default_verifiers"
      contains: "RecurringScheduleVerifier"
    - path: "lib/source_monitor.rb"
      provides: "Autoload declaration for RecurringScheduleVerifier"
      contains: "autoload :RecurringScheduleVerifier"
    - path: "test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb"
      provides: "Tests covering all RecurringScheduleVerifier branches"
      contains: "class RecurringScheduleVerifierTest"
  key_links:
    - from: "recurring_schedule_verifier.rb"
      to: "REQ-19"
      via: "Checks whether recurring tasks are registered with SolidQueue dispatchers"
    - from: "solid_queue_verifier.rb#warning_result remediation"
      to: "REQ-20"
      via: "Remediation now suggests Procfile.dev for bin/dev users"
    - from: "runner.rb#default_verifiers"
      to: "recurring_schedule_verifier.rb"
      via: "Runner includes RecurringScheduleVerifier in the default verifier set"
---
<objective>
Add a RecurringScheduleVerifier to the verification suite that checks whether recurring tasks are registered with Solid Queue (REQ-19), and enhance the SolidQueueVerifier remediation message to suggest Procfile.dev when workers are not detected (REQ-20). Wire the new verifier into the Runner and autoload system.
</objective>
<context>
@lib/source_monitor/setup/verification/solid_queue_verifier.rb -- The existing verifier to enhance. Constructor accepts `process_relation:`, `connection:`, `clock:` with defaults. The `call` method returns a Result via helper methods `ok_result`, `warning_result`, `error_result`. Key change: line 24's warning_result remediation string must be updated to mention Procfile.dev. Follow the exact same pattern for the new verifier. Key: `:solid_queue`, name: `"Solid Queue"`.

@lib/source_monitor/setup/verification/action_cable_verifier.rb -- Pattern reference for verifier design. Shows constructor dependency injection, `call` method with case/when branching, rescue StandardError, and Result helpers. The new RecurringScheduleVerifier should follow the same structure.

@lib/source_monitor/setup/verification/result.rb -- Result struct with `key`, `name`, `status`, `details`, `remediation` and status predicates (`ok?`, `warning?`, `error?`). Summary aggregates results. The new verifier should use key: `:recurring_schedule`, name: `"Recurring Schedule"`.

@lib/source_monitor/setup/verification/runner.rb -- Orchestrator with `default_verifiers` returning an array. Currently `[SolidQueueVerifier.new, ActionCableVerifier.new]`. Add `RecurringScheduleVerifier.new` to this array.

@test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb -- Test pattern: uses FakeRelation and FakeConnection structs, tests all branches (ok, warning, error for missing gem, missing tables, unexpected failure). The "warns when no recent workers" test should be updated to assert the new remediation mentions Procfile.dev.

@test/lib/source_monitor/setup/verification/runner_test.rb -- Tests Runner with stub verifiers. The "uses default verifiers" test stubs SolidQueueVerifier and ActionCableVerifier via `.stub(:new, ...)`. Must add a third stub for RecurringScheduleVerifier and update assertions to expect 3 results.

@lib/source_monitor.rb lines 169-177 -- Autoload declarations for Setup::Verification module. Add `autoload :RecurringScheduleVerifier` here.

@lib/source_monitor/engine.rb lines 54-60 -- Shows how `SolidQueue::RecurringTask` is used elsewhere in the codebase. The model has columns: key, class_name, command, schedule, queue_name, static. Tasks with `class_name` starting with "SourceMonitor::" or `command` containing "SourceMonitor::" are SourceMonitor-owned entries.

@test/dummy/config/recurring.yml -- Shows the 5 recurring tasks configured for the dummy app: source_monitor_schedule_fetches, source_monitor_schedule_scrapes, source_monitor_item_cleanup, source_monitor_log_cleanup, clear_solid_queue_finished_jobs. The first 4 are SourceMonitor-owned (keys start with `source_monitor_` or class_name/command references SourceMonitor::).

**Rationale:** The RecurringScheduleVerifier checks that recurring tasks (defined in recurring.yml) are actually loaded into the solid_queue_recurring_tasks table. This catches the common failure where a user has the YAML file but the dispatcher is not configured with `recurring_schedule: config/recurring.yml`, so tasks never get registered. The verifier queries `SolidQueue::RecurringTask` and looks for entries whose key starts with `source_monitor_` OR whose class_name/command references `SourceMonitor::`.

**Key design decisions:**
1. Check for `SolidQueue::RecurringTask` availability (same pattern as SolidQueueVerifier checking Process)
2. Check table existence before querying (same pattern)
3. Query for any recurring tasks, then filter for SourceMonitor-specific ones
4. Four outcomes: (a) ok if SM tasks found, (b) warning if tasks exist but no SM ones, (c) warning if no tasks at all, (d) error if SolidQueue unavailable
5. SourceMonitor task detection: key starts with `source_monitor_` OR class_name starts with `SourceMonitor::` OR command contains `SourceMonitor::`
6. Inject `task_relation:` and `connection:` via constructor for testability
</context>
<tasks>
<task type="auto">
  <name>create-recurring-schedule-verifier</name>
  <files>
    lib/source_monitor/setup/verification/recurring_schedule_verifier.rb
  </files>
  <action>
Create a new file `lib/source_monitor/setup/verification/recurring_schedule_verifier.rb` following the exact pattern of SolidQueueVerifier and ActionCableVerifier.

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class RecurringScheduleVerifier
        SOURCE_MONITOR_KEY_PREFIX = "source_monitor_"
        SOURCE_MONITOR_NAMESPACE = "SourceMonitor::"

        def initialize(task_relation: default_task_relation, connection: default_connection)
          @task_relation = task_relation
          @connection = connection
        end

        def call
          return missing_gem_result unless task_relation
          return missing_tables_result unless tables_present?

          tasks = all_tasks
          sm_tasks = source_monitor_tasks(tasks)

          if sm_tasks.any?
            ok_result("#{sm_tasks.size} SourceMonitor recurring task(s) registered")
          elsif tasks.any?
            warning_result(
              "Recurring tasks exist but none belong to SourceMonitor",
              "Add SourceMonitor entries to config/recurring.yml and ensure the dispatcher has `recurring_schedule: config/recurring.yml`"
            )
          else
            warning_result(
              "No recurring tasks are registered with Solid Queue",
              "Configure a dispatcher with `recurring_schedule: config/recurring.yml` in config/queue.yml and ensure recurring.yml contains SourceMonitor task entries"
            )
          end
        rescue StandardError => e
          error_result(
            "Recurring schedule verification failed: #{e.message}",
            "Verify Solid Queue migrations are up to date and the dispatcher is configured with recurring_schedule"
          )
        end

        private

        attr_reader :task_relation, :connection

        def default_task_relation
          SolidQueue::RecurringTask if defined?(SolidQueue::RecurringTask)
        end

        def default_connection
          SolidQueue::RecurringTask.connection if defined?(SolidQueue::RecurringTask)
        rescue StandardError
          nil
        end

        def tables_present?
          return false unless connection

          connection.table_exists?(task_relation.table_name)
        end

        def all_tasks
          task_relation.all.to_a
        end

        def source_monitor_tasks(tasks)
          tasks.select do |task|
            task.key.start_with?(SOURCE_MONITOR_KEY_PREFIX) ||
              task.class_name.to_s.start_with?(SOURCE_MONITOR_NAMESPACE) ||
              task.command.to_s.include?(SOURCE_MONITOR_NAMESPACE)
          end
        end

        def missing_gem_result
          error_result(
            "Solid Queue gem is not available",
            "Add `solid_queue` to your Gemfile and bundle install"
          )
        end

        def missing_tables_result
          error_result(
            "Solid Queue recurring tasks table is missing",
            "Run `rails solid_queue:install` or copy the engine's Solid Queue migration"
          )
        end

        def ok_result(details)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :ok, details: details)
        end

        def warning_result(details, remediation)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :warning, details: details, remediation: remediation)
        end

        def error_result(details, remediation)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :error, details: details, remediation: remediation)
        end
      end
    end
  end
end
```

Key design points:
- Constructor accepts `task_relation:` and `connection:` for dependency injection (testability)
- Defaults to `SolidQueue::RecurringTask` if available
- `all_tasks` fetches all recurring tasks, then `source_monitor_tasks` filters by key prefix, class_name namespace, or command namespace
- Three-tier result: ok (SM tasks found), warning (tasks exist but no SM ones OR no tasks at all), error (gem/table missing or unexpected failure)
- Same rescue StandardError pattern as other verifiers
  </action>
  <verify>
Read the created file and confirm: (a) class is in the correct module nesting, (b) constructor follows dependency injection pattern, (c) `call` method handles all 5 outcomes (missing gem, missing tables, SM tasks found, non-SM tasks only, no tasks), (d) helper methods are private, (e) Result key is `:recurring_schedule`.
  </verify>
  <done>
RecurringScheduleVerifier created with full branch coverage: missing gem, missing tables, SM tasks found (ok), non-SM tasks only (warning), no tasks (warning), unexpected error.
  </done>
</task>
<task type="auto">
  <name>enhance-solid-queue-verifier-remediation</name>
  <files>
    lib/source_monitor/setup/verification/solid_queue_verifier.rb
    test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb
  </files>
  <action>
**Modify `lib/source_monitor/setup/verification/solid_queue_verifier.rb`:**

Change the remediation string on line 24 from:
```ruby
"Start a Solid Queue worker with `bin/rails solid_queue:start` and ensure it stays running"
```
to:
```ruby
"Start a Solid Queue worker with `bin/rails solid_queue:start` or add `jobs: bundle exec rake solid_queue:start` to Procfile.dev and run `bin/dev`"
```

This is a single-line change in the `call` method's warning_result call (the "no recent workers" branch).

**Modify `test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb`:**

Update the "warns when no recent workers" test to also assert the remediation message mentions Procfile.dev:
```ruby
assert_match(/Procfile\.dev/, result.remediation)
```

Add this assertion after the existing `assert_match(/No Solid Queue workers/, result.details)` line.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb` -- all 5 tests pass. Run `bin/rubocop lib/source_monitor/setup/verification/solid_queue_verifier.rb` -- 0 offenses. Grep for "Procfile.dev" in the verifier file confirms the new remediation text.
  </verify>
  <done>
SolidQueueVerifier remediation now mentions Procfile.dev with the `bin/dev` workflow. Existing test updated to assert the new message content. REQ-20 satisfied.
  </done>
</task>
<task type="auto">
  <name>add-recurring-schedule-verifier-tests</name>
  <files>
    test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb
  </files>
  <action>
Create a new test file following the exact pattern from `solid_queue_verifier_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class RecurringScheduleVerifierTest < ActiveSupport::TestCase
        # Fake task struct matching SolidQueue::RecurringTask's interface
        FakeTask = Struct.new(:key, :class_name, :command, keyword_init: true)

        # Fake relation that returns tasks and supports table_name
        class FakeTaskRelation
          attr_reader :table_name

          def initialize(tasks, table_name: "solid_queue_recurring_tasks")
            @tasks = tasks
            @table_name = table_name
          end

          def all
            self
          end

          def to_a
            @tasks
          end
        end

        class FakeConnection
          def initialize(tables: [])
            @tables = tables
          end

          def table_exists?(name)
            @tables.include?(name)
          end
        end

        test "returns ok when source monitor recurring tasks are registered" do
          tasks = [
            FakeTask.new(key: "source_monitor_schedule_fetches", class_name: "SourceMonitor::ScheduleFetchesJob", command: nil),
            FakeTask.new(key: "source_monitor_item_cleanup", class_name: "SourceMonitor::ItemCleanupJob", command: nil)
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: ["solid_queue_recurring_tasks"])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :ok, result.status
          assert_match(/2 SourceMonitor recurring task/, result.details)
        end

        test "returns ok when source monitor tasks detected by command" do
          tasks = [
            FakeTask.new(key: "source_monitor_schedule_scrapes", class_name: nil, command: "SourceMonitor::Scraping::Scheduler.run(limit: 100)")
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: ["solid_queue_recurring_tasks"])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :ok, result.status
        end

        test "warns when tasks exist but none belong to source monitor" do
          tasks = [
            FakeTask.new(key: "other_app_cleanup", class_name: "OtherApp::CleanupJob", command: nil)
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: ["solid_queue_recurring_tasks"])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :warning, result.status
          assert_match(/none belong to SourceMonitor/, result.details)
          assert_match(/recurring\.yml/, result.remediation)
        end

        test "warns when no recurring tasks are registered" do
          relation = FakeTaskRelation.new([])
          connection = FakeConnection.new(tables: ["solid_queue_recurring_tasks"])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :warning, result.status
          assert_match(/No recurring tasks are registered/, result.details)
          assert_match(/recurring_schedule/, result.remediation)
        end

        test "errors when solid queue gem is missing" do
          result = RecurringScheduleVerifier.new(task_relation: nil, connection: nil).call

          assert_equal :error, result.status
          assert_match(/gem is not available/, result.details)
        end

        test "errors when recurring tasks table is missing" do
          relation = FakeTaskRelation.new([], table_name: "solid_queue_recurring_tasks")
          connection = FakeConnection.new(tables: [])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :error, result.status
          assert_match(/table is missing/, result.details)
        end

        test "rescues unexpected failures and reports remediation" do
          relation = Class.new do
            def table_name = "solid_queue_recurring_tasks"
            def all = raise "boom"
          end.new
          connection = FakeConnection.new(tables: ["solid_queue_recurring_tasks"])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :error, result.status
          assert_match(/verification failed/i, result.details)
          assert_match(/dispatcher/, result.remediation)
        end
      end
    end
  end
end
```

7 tests covering all branches: ok (by key prefix), ok (by command), warning (non-SM tasks), warning (no tasks), error (missing gem), error (missing table), error (unexpected exception).
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb` -- all 7 tests pass. Run `bin/rubocop test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb` -- 0 offenses.
  </verify>
  <done>
7 tests covering all RecurringScheduleVerifier branches pass. RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>wire-into-runner-and-autoload</name>
  <files>
    lib/source_monitor/setup/verification/runner.rb
    lib/source_monitor.rb
    test/lib/source_monitor/setup/verification/runner_test.rb
  </files>
  <action>
**Modify `lib/source_monitor/setup/verification/runner.rb`:**

Add `RecurringScheduleVerifier.new` to the `default_verifiers` array (line 21). The array should become:
```ruby
def default_verifiers
  [ SolidQueueVerifier.new, RecurringScheduleVerifier.new, ActionCableVerifier.new ]
end
```

Place RecurringScheduleVerifier between SolidQueue and ActionCable -- it logically groups with SolidQueue (both check SQ state) and should run after the worker heartbeat check but before the ActionCable check.

**Modify `lib/source_monitor.rb`:**

Add the autoload declaration in the `module Verification` block (around line 174), after the ActionCableVerifier line:
```ruby
autoload :RecurringScheduleVerifier, "source_monitor/setup/verification/recurring_schedule_verifier"
```

**Modify `test/lib/source_monitor/setup/verification/runner_test.rb`:**

Update the "uses default verifiers" test:
1. Add a recurring_result: `recurring_result = Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :ok, details: "ok")`
2. Add a recurring_double: `recurring_double = verifier_double.new(recurring_result)`
3. Add a third stub inside the existing stub blocks: `RecurringScheduleVerifier.stub(:new, ->(*) { recurring_double }) do`
4. Update assertion: `assert_equal 3, summary.results.size`
5. Add: `assert_equal 1, recurring_double.calls`
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` -- all tests pass. Grep for `RecurringScheduleVerifier` in runner.rb and source_monitor.rb confirms wiring.
  </verify>
  <done>
RecurringScheduleVerifier wired into Runner.default_verifiers and autoloaded from lib/source_monitor.rb. Runner test updated to expect 3 verifiers.
  </done>
</task>
<task type="auto">
  <name>full-suite-verification</name>
  <files>
    lib/source_monitor/setup/verification/recurring_schedule_verifier.rb
    lib/source_monitor/setup/verification/solid_queue_verifier.rb
    lib/source_monitor/setup/verification/runner.rb
    test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb
    test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb
    test/lib/source_monitor/setup/verification/runner_test.rb
  </files>
  <action>
Run the full test suite and linting to confirm no regressions:

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/` -- all verification tests pass (existing + new)
2. `bin/rails test` -- full suite passes with 867+ runs and 0 failures
3. `bin/rubocop lib/source_monitor/setup/verification/ test/lib/source_monitor/setup/verification/` -- zero offenses
4. `bin/brakeman --no-pager` -- zero warnings
5. Review the final state of all modified files to confirm:
   - RecurringScheduleVerifier follows the exact same pattern as SolidQueueVerifier
   - SolidQueueVerifier remediation mentions Procfile.dev
   - Runner.default_verifiers includes all 3 verifiers
   - Autoload declaration is in the correct module block
   - All tests cover the expected branches

If any test failures or RuboCop offenses are found, fix them before completing.
  </action>
  <verify>
`bin/rails test` exits 0 with 867+ runs, 0 failures. `bin/rubocop` exits 0 with 0 offenses. `bin/brakeman --no-pager` exits 0 with 0 warnings.
  </verify>
  <done>
Full test suite passes. RuboCop clean. Brakeman clean. All REQ-19, REQ-20 acceptance criteria met.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/recurring_schedule_verifier_test.rb` -- 7 tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb` -- 5 tests pass with updated assertion
3. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` -- 2 tests pass with 3-verifier expectation
4. `bin/rails test` -- 867+ runs, 0 failures
5. `bin/rubocop` -- 0 offenses
6. `bin/brakeman --no-pager` -- 0 warnings
7. `grep -n 'class RecurringScheduleVerifier' lib/source_monitor/setup/verification/recurring_schedule_verifier.rb` returns a match
8. `grep -n 'Procfile.dev' lib/source_monitor/setup/verification/solid_queue_verifier.rb` returns a match
9. `grep -n 'RecurringScheduleVerifier' lib/source_monitor/setup/verification/runner.rb` returns a match
10. `grep -n 'RecurringScheduleVerifier' lib/source_monitor.rb` returns a match
</verification>
<success_criteria>
- RecurringScheduleVerifier returns ok when SourceMonitor recurring tasks are registered (REQ-19)
- RecurringScheduleVerifier warns when recurring tasks exist but none belong to SourceMonitor (REQ-19)
- RecurringScheduleVerifier warns when no recurring tasks are registered at all (REQ-19)
- RecurringScheduleVerifier errors when SolidQueue gem is missing (REQ-19)
- RecurringScheduleVerifier errors when recurring tasks table is missing (REQ-19)
- SolidQueueVerifier remediation mentions Procfile.dev and bin/dev (REQ-20)
- RecurringScheduleVerifier is included in Runner.default_verifiers
- RecurringScheduleVerifier is autoloaded from lib/source_monitor.rb
- All existing tests continue to pass (no regressions)
- 7+ new RecurringScheduleVerifier tests cover all branches
- RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/02-verification/PLAN-01-SUMMARY.md
</output>
