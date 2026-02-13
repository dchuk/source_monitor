---
phase: 1
plan: "01"
title: procfile-queue-generator-steps
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - lib/generators/source_monitor/install/install_generator.rb
  - test/lib/generators/install_generator_test.rb
  - lib/source_monitor/setup/procfile_patcher.rb
  - lib/source_monitor/setup/queue_config_patcher.rb
  - lib/source_monitor/setup/workflow.rb
  - test/lib/source_monitor/setup/workflow_test.rb
must_haves:
  truths:
    - "Running `bin/rails test test/lib/generators/install_generator_test.rb` exits 0 with 0 failures"
    - "Running `bin/rails test test/lib/source_monitor/setup/workflow_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/generators/source_monitor/install/install_generator.rb lib/source_monitor/setup/procfile_patcher.rb lib/source_monitor/setup/queue_config_patcher.rb lib/source_monitor/setup/workflow.rb` exits 0 with no offenses"
    - "Running the generator against an empty destination creates a Procfile.dev with both `web:` and `jobs:` lines"
    - "Running the generator against an existing Procfile.dev that has no `jobs:` line appends one"
    - "Running the generator against an existing Procfile.dev that already has a `jobs:` line skips with say_status :skip"
    - "Running the generator against a queue.yml with dispatchers but no recurring_schedule adds it"
    - "Running the generator against a queue.yml that already has recurring_schedule skips"
  artifacts:
    - path: "lib/generators/source_monitor/install/install_generator.rb"
      provides: "Procfile.dev and queue.yml generator steps"
      contains: "def patch_procfile_dev"
    - path: "lib/generators/source_monitor/install/install_generator.rb"
      provides: "queue.yml dispatcher patching"
      contains: "def configure_queue_dispatcher"
    - path: "test/lib/generators/install_generator_test.rb"
      provides: "Tests for both new generator steps"
      contains: "test_creates_procfile_dev_when_none_exists"
    - path: "lib/source_monitor/setup/procfile_patcher.rb"
      provides: "Workflow helper for Procfile.dev patching"
      contains: "class ProcfilePatcher"
    - path: "lib/source_monitor/setup/queue_config_patcher.rb"
      provides: "Workflow helper for queue.yml patching"
      contains: "class QueueConfigPatcher"
    - path: "lib/source_monitor/setup/workflow.rb"
      provides: "Workflow integration of both new steps"
      contains: "procfile_patcher"
  key_links:
    - from: "install_generator.rb#patch_procfile_dev"
      to: "REQ-16"
      via: "Generator patches Procfile.dev with jobs: entry"
    - from: "install_generator.rb#configure_queue_dispatcher"
      to: "REQ-17"
      via: "Generator patches queue config with recurring_schedule"
    - from: "workflow.rb"
      to: "REQ-18"
      via: "Guided workflow integrates both new steps"
---
<objective>
Add two new idempotent steps to the install generator (Procfile.dev patching and queue.yml dispatcher wiring) and integrate both into the guided Setup::Workflow. All steps must follow existing generator conventions: idempotent, skip-if-present, say_status output. REQ-16, REQ-17, REQ-18.
</objective>
<context>
@lib/generators/source_monitor/install/install_generator.rb -- The existing generator with 3 public steps: add_routes_mount, create_initializer, configure_recurring_jobs. New steps must be added as public methods BEFORE print_next_steps (Rails generators execute public methods in definition order). Each step follows the pattern: check-if-already-done -> skip with say_status :skip OR perform action with say_status :create/:append. The recurring jobs step is the best pattern to follow -- it handles both fresh-file and existing-file cases with YAML parsing.

@test/lib/generators/install_generator_test.rb -- 11 existing tests using Rails::Generators::TestCase. Tests use `run_generator` to execute, `assert_file` to check contents, and manually create pre-existing files in `destination_root` to test idempotent skip paths. The WORKER_SUFFIX pattern handles parallel test isolation. New tests should follow the same patterns.

@lib/source_monitor/setup/workflow.rb -- The guided installer. Collaborators are injected via constructor kwargs with defaults. The `run` method calls them in sequence. New patchers should be added AFTER `install_generator.run` (which runs the generator) and BEFORE `verifier.call`. Two new kwargs needed: `procfile_patcher:` and `queue_config_patcher:`.

@lib/source_monitor/setup/install_generator.rb -- Existing wrapper that shells out to `bin/rails generate source_monitor:install`. The generator handles Procfile.dev and queue.yml, so the workflow helpers only need to handle the guided-mode post-generator patching if the generator didn't run (edge case) OR to provide explicit say-status output in the guided flow. However, since the workflow already delegates to the generator, the simplest approach is to add the patching logic directly to the generator (which the workflow already calls) and add lightweight workflow helpers that handle standalone guided-mode usage.

@test/lib/source_monitor/setup/workflow_test.rb -- Uses Spy objects and Minitest::Mock for all collaborators. New patchers need Spy instances in test setup. Existing test "run orchestrates all installers" expects a specific prompter call count -- adding new steps MUST NOT add new prompter calls (the patching is unconditional, no user prompt needed).

@.vbw-planning/phases/01-generator-steps/01-CONTEXT.md -- Phase context with user decisions and acceptance criteria.

**Rationale:** The generator is the primary entry point -- both `bin/rails g source_monitor:install` and the guided workflow funnel through it. Adding the steps directly to the generator ensures both paths are covered. The workflow helpers provide explicit visibility in the guided flow.

**Key design decisions:**
1. Procfile.dev default content: `web: bin/rails server -p 3000\njobs: bundle exec rake solid_queue:start` (standard Rails 8 Procfile.dev pattern)
2. The `jobs:` line check should match any line starting with `jobs:` (case-sensitive, anchored to line start)
3. Queue.yml patching targets any dispatcher block under any environment key and adds `recurring_schedule: config/recurring.yml` if not present
4. Queue.yml patching must handle both `default: &default` with env aliases AND flat per-environment configs
5. If queue.yml does not exist, skip with a helpful message (the file is Rails-generated; creating it from scratch could conflict with the host app's queue backend choice)
</context>
<tasks>
<task type="auto">
  <name>add-procfile-dev-generator-step</name>
  <files>
    lib/generators/source_monitor/install/install_generator.rb
  </files>
  <action>
Add a new public method `patch_procfile_dev` to InstallGenerator, placed AFTER `configure_recurring_jobs` and BEFORE `print_next_steps`. This ensures Rails generators execute it in the correct order.

The method must:
1. Build the Procfile.dev path: `File.join(destination_root, "Procfile.dev")`
2. If the file exists AND already contains a line matching `/^jobs:/` -> `say_status :skip, "Procfile.dev (jobs entry already present)", :yellow` and return
3. If the file exists but has no `jobs:` line -> append `\njobs: bundle exec rake solid_queue:start\n` to the file, then `say_status :append, "Procfile.dev", :green`
4. If the file does not exist -> create it with content:
   ```
   web: bin/rails server -p 3000
   jobs: bundle exec rake solid_queue:start
   ```
   Then `say_status :create, "Procfile.dev", :green`

Add a private constant for the jobs line:
```ruby
PROCFILE_JOBS_ENTRY = "jobs: bundle exec rake solid_queue:start"
```

Update `print_next_steps` to mention Procfile.dev:
```ruby
say_status :info,
  "Procfile.dev configured -- run bin/dev to start both web server and Solid Queue workers.",
  :green
```
  </action>
  <verify>
Read the modified file and confirm: (a) `patch_procfile_dev` is defined between `configure_recurring_jobs` and `print_next_steps`, (b) it handles all 3 cases (create, append, skip), (c) the PROCFILE_JOBS_ENTRY constant is in the private section.
  </verify>
  <done>
The generator has a `patch_procfile_dev` method that creates, appends to, or skips Procfile.dev depending on current state. The method follows the same idempotent pattern as `configure_recurring_jobs`.
  </done>
</task>
<task type="auto">
  <name>add-queue-config-generator-step</name>
  <files>
    lib/generators/source_monitor/install/install_generator.rb
  </files>
  <action>
Add a new public method `configure_queue_dispatcher` to InstallGenerator, placed AFTER `patch_procfile_dev` and BEFORE `print_next_steps`.

The method must:
1. Build the queue.yml path: `File.join(destination_root, "config/queue.yml")`
2. If the file does not exist -> `say_status :skip, "config/queue.yml (file not found -- create it or run rails app:update to generate)", :yellow` and return
3. Read and parse the YAML with `YAML.safe_load(File.read(path), aliases: true)`
4. If the parsed content already contains `recurring_schedule` anywhere in any dispatcher entry -> `say_status :skip, "config/queue.yml (recurring_schedule already configured)", :yellow` and return
5. Otherwise, find dispatcher entries and add `"recurring_schedule" => "config/recurring.yml"` to each one. The structure is:
   - Environment-based: `{ "default" => { "dispatchers" => [{ "polling_interval" => 1 }] } }`
   - Or flat: `{ "dispatchers" => [{ "polling_interval" => 1 }] }`
6. Write back the modified YAML and `say_status :append, "config/queue.yml (added recurring_schedule to dispatchers)", :green`

Add a private helper `queue_config_has_recurring_schedule?(parsed)` that recursively checks if any hash value under `dispatchers` contains `recurring_schedule`.

Add a private helper `add_recurring_schedule_to_dispatchers!(parsed)` that walks the parsed hash and adds `"recurring_schedule" => "config/recurring.yml"` to each dispatcher hash that lacks it.

**Important edge case:** If the queue.yml has no `dispatchers` key at any level, add a default dispatcher section:
```yaml
dispatchers:
  - polling_interval: 1
    batch_size: 500
    recurring_schedule: config/recurring.yml
```

Write back using `YAML.dump` (the file is machine-managed YAML, not hand-formatted like recurring.yml).
  </action>
  <verify>
Read the modified file and confirm: (a) `configure_queue_dispatcher` is defined between `patch_procfile_dev` and `print_next_steps`, (b) it handles all cases (missing file, already configured, needs patching, no dispatchers key), (c) helper methods are private.
  </verify>
  <done>
The generator has a `configure_queue_dispatcher` method that patches queue.yml dispatchers with recurring_schedule. It handles missing files, already-configured files, and files needing patching.
  </done>
</task>
<task type="auto">
  <name>add-generator-tests</name>
  <files>
    test/lib/generators/install_generator_test.rb
  </files>
  <action>
Add the following tests to InstallGeneratorTest, following existing patterns:

**Procfile.dev tests:**

1. `test_creates_procfile_dev_when_none_exists` -- Run generator, assert Procfile.dev exists with both `web:` and `jobs:` lines.

2. `test_appends_jobs_entry_to_existing_procfile_dev` -- Create a Procfile.dev with only `web: bin/rails server -p 3000`, run generator, assert file now contains `jobs:` line AND still contains `web:` line.

3. `test_skips_procfile_dev_when_jobs_entry_already_present` -- Create a Procfile.dev with `web:` and `jobs:` lines, run generator, capture output, assert output contains "skip".

4. `test_does_not_duplicate_jobs_entry_when_rerun` -- Run generator twice, assert Procfile.dev contains exactly 1 line matching `/^jobs:/`.

**Queue config tests:**

5. `test_patches_queue_yml_dispatcher_with_recurring_schedule` -- Create a config/queue.yml with dispatchers section (no recurring_schedule), run generator, assert file contains `recurring_schedule`.

6. `test_skips_queue_yml_when_recurring_schedule_already_present` -- Create a config/queue.yml that already has `recurring_schedule: config/recurring.yml` in the dispatcher, run generator, capture output, assert output contains "skip".

7. `test_skips_queue_yml_when_file_missing` -- Do NOT create config/queue.yml, run generator, capture output, assert output contains "skip" and "not found".

8. `test_adds_default_dispatcher_when_none_exists_in_queue_yml` -- Create a config/queue.yml with queues but no dispatchers section, run generator, assert file now contains both `dispatchers` and `recurring_schedule`.

For queue.yml tests, create realistic YAML content matching the Rails 8 default structure (from host_app_harness.rb):
```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      polling_interval: 0.1

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

Use `File.join(destination_root, "config")` + `FileUtils.mkdir_p` to create pre-existing files, matching the pattern from `test_merges_into_existing_recurring_yml_with_default_key`.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/generators/install_generator_test.rb` and confirm all tests pass (existing + new). Run `bin/rubocop test/lib/generators/install_generator_test.rb` and confirm no offenses.
  </verify>
  <done>
8 new tests covering all Procfile.dev and queue.yml scenarios. All 19 tests (11 existing + 8 new) pass. RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>add-workflow-helpers-and-integration</name>
  <files>
    lib/source_monitor/setup/procfile_patcher.rb
    lib/source_monitor/setup/queue_config_patcher.rb
    lib/source_monitor/setup/workflow.rb
    test/lib/source_monitor/setup/workflow_test.rb
  </files>
  <action>
**Create `lib/source_monitor/setup/procfile_patcher.rb`:**

Follow the pattern from `install_generator.rb` (the setup wrapper, not the Rails generator). This is a lightweight wrapper that patches Procfile.dev in the host app's root directory. Since the Rails generator already handles this when run via `bin/rails g source_monitor:install`, this helper exists for guided workflow usage where explicit step visibility is desired.

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Setup
    class ProcfilePatcher
      JOBS_ENTRY = "jobs: bundle exec rake solid_queue:start"

      def initialize(path: "Procfile.dev")
        @path = Pathname.new(path)
      end

      def patch
        if path.exist?
          content = path.read
          return false if content.match?(/^jobs:/)
          path.open("a") { |f| f.puts("", JOBS_ENTRY) }
        else
          path.write("web: bin/rails server -p 3000\n#{JOBS_ENTRY}\n")
        end
        true
      end

      private

      attr_reader :path
    end
  end
end
```

**Create `lib/source_monitor/setup/queue_config_patcher.rb`:**

```ruby
# frozen_string_literal: true

require "yaml"

module SourceMonitor
  module Setup
    class QueueConfigPatcher
      RECURRING_SCHEDULE_VALUE = "config/recurring.yml"

      def initialize(path: "config/queue.yml")
        @path = Pathname.new(path)
      end

      def patch
        return false unless path.exist?

        parsed = YAML.safe_load(path.read, aliases: true) || {}
        return false if has_recurring_schedule?(parsed)

        add_recurring_schedule!(parsed)
        path.write(YAML.dump(parsed))
        true
      end

      private

      attr_reader :path

      # (include the same recursive helpers as the generator)
    end
  end
end
```

**Modify `lib/source_monitor/setup/workflow.rb`:**

1. Add `require_relative "procfile_patcher"` and `require_relative "queue_config_patcher"` at the top (after existing require_relative lines).
2. Add two new kwargs to `initialize`: `procfile_patcher: ProcfilePatcher.new` and `queue_config_patcher: QueueConfigPatcher.new`.
3. Store them as instance variables and add to `attr_reader`.
4. In the `run` method, call both AFTER `initializer_patcher.ensure_navigation_hint` and BEFORE the devise check:
   ```ruby
   procfile_patcher.patch
   queue_config_patcher.patch
   ```
   These are unconditional (no user prompt -- maximum hand-holding per user decision).

**Modify `test/lib/source_monitor/setup/workflow_test.rb`:**

1. In the "run orchestrates all installers" test: add `procfile_patcher = Spy.new(true)` and `queue_config_patcher = Spy.new(true)`, pass them to `Workflow.new`, and assert `assert_equal :patch, procfile_patcher.calls.first.first` and `assert_equal :patch, queue_config_patcher.calls.first.first`.
2. In ALL other tests that construct a Workflow: add `procfile_patcher: Spy.new(true)` and `queue_config_patcher: Spy.new(true)` kwargs to prevent test failures from missing the new required collaborators (they have defaults, but the Spy pattern is used for isolation).
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/workflow_test.rb` and confirm all tests pass. Run `bin/rubocop lib/source_monitor/setup/procfile_patcher.rb lib/source_monitor/setup/queue_config_patcher.rb lib/source_monitor/setup/workflow.rb` and confirm no offenses.
  </verify>
  <done>
Two new workflow helper classes created. Workflow.rb wires both patchers into the guided install flow. All workflow tests pass with the new collaborators injected. RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>full-suite-verification</name>
  <files>
    lib/generators/source_monitor/install/install_generator.rb
    test/lib/generators/install_generator_test.rb
    lib/source_monitor/setup/workflow.rb
    test/lib/source_monitor/setup/workflow_test.rb
  </files>
  <action>
Run the full test suite and linting to confirm no regressions:

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/generators/install_generator_test.rb test/lib/source_monitor/setup/workflow_test.rb` -- all targeted tests pass
2. `bin/rails test` -- full suite passes with 841+ runs and 0 failures
3. `bin/rubocop` -- zero offenses
4. Review the final state of all modified files to confirm:
   - Generator public methods are in correct order: add_routes_mount, create_initializer, configure_recurring_jobs, patch_procfile_dev, configure_queue_dispatcher, print_next_steps
   - All new private methods and constants are in the private section
   - Workflow constructor has all collaborators with sensible defaults
   - Workflow.run calls patchers in correct position (after generator, before verifier)

If any test failures or RuboCop offenses are found, fix them before completing.
  </action>
  <verify>
`bin/rails test` exits 0 with 841+ runs, 0 failures. `bin/rubocop` exits 0 with 0 offenses. `bin/brakeman --no-pager` exits 0 with 0 warnings.
  </verify>
  <done>
Full test suite passes. RuboCop clean. Brakeman clean. All REQ-16, REQ-17, REQ-18 acceptance criteria met.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/generators/install_generator_test.rb` -- 19+ tests pass (11 existing + 8 new)
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/workflow_test.rb` -- all workflow tests pass
3. `bin/rails test` -- 841+ runs, 0 failures
4. `bin/rubocop` -- 0 offenses
5. `bin/brakeman --no-pager` -- 0 warnings
6. `grep -n 'def patch_procfile_dev' lib/generators/source_monitor/install/install_generator.rb` returns a match
7. `grep -n 'def configure_queue_dispatcher' lib/generators/source_monitor/install/install_generator.rb` returns a match
8. `grep -n 'procfile_patcher' lib/source_monitor/setup/workflow.rb` returns matches in initialize and run
9. `grep -n 'queue_config_patcher' lib/source_monitor/setup/workflow.rb` returns matches in initialize and run
</verification>
<success_criteria>
- Generator creates Procfile.dev with web: + jobs: entries when none exists (REQ-16)
- Generator appends jobs: entry to existing Procfile.dev without duplicating (REQ-16)
- Generator skips Procfile.dev when jobs: entry already present (REQ-16 idempotency)
- Generator patches queue.yml dispatchers with recurring_schedule (REQ-17)
- Generator skips queue.yml when recurring_schedule already configured (REQ-17 idempotency)
- Generator handles missing queue.yml gracefully (REQ-17 edge case)
- Guided workflow runs both patchers after generator step (REQ-18)
- All existing tests continue to pass (no regressions)
- 8+ new generator tests cover all scenarios
- RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/01-generator-steps/PLAN-01-SUMMARY.md
</output>
