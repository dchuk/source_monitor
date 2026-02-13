---
phase: 1
plan: "01"
title: upgrade-command-and-migration-verifier
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - lib/source_monitor/setup/verification/pending_migrations_verifier.rb
  - lib/source_monitor/setup/verification/runner.rb
  - lib/source_monitor/setup/upgrade_command.rb
  - lib/source_monitor/setup/cli.rb
  - lib/source_monitor.rb
  - test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb
  - test/lib/source_monitor/setup/verification/runner_test.rb
  - test/lib/source_monitor/setup/upgrade_command_test.rb
  - test/lib/source_monitor/setup/cli_test.rb
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/upgrade_command_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/cli_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/setup/verification/pending_migrations_verifier.rb lib/source_monitor/setup/upgrade_command.rb lib/source_monitor/setup/cli.rb` exits 0 with no offenses"
    - "Running `bin/rails test` exits 0 with 973+ runs and 0 failures"
  artifacts:
    - path: "lib/source_monitor/setup/verification/pending_migrations_verifier.rb"
      provides: "Verifier that checks for unmigrated SourceMonitor migrations (REQ-27)"
      contains: "class PendingMigrationsVerifier"
    - path: "lib/source_monitor/setup/upgrade_command.rb"
      provides: "Upgrade orchestrator that detects version changes and runs remediation (REQ-26)"
      contains: "class UpgradeCommand"
    - path: "lib/source_monitor/setup/cli.rb"
      provides: "CLI entry point with upgrade subcommand"
      contains: "def upgrade"
    - path: "lib/source_monitor/setup/verification/runner.rb"
      provides: "Runner wires PendingMigrationsVerifier into default_verifiers"
      contains: "PendingMigrationsVerifier"
    - path: "lib/source_monitor.rb"
      provides: "Autoload declarations for PendingMigrationsVerifier and UpgradeCommand"
      contains: "autoload :PendingMigrationsVerifier"
    - path: "test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb"
      provides: "Tests covering all PendingMigrationsVerifier branches"
      contains: "class PendingMigrationsVerifierTest"
    - path: "test/lib/source_monitor/setup/upgrade_command_test.rb"
      provides: "Tests covering UpgradeCommand version detection and orchestration"
      contains: "class UpgradeCommandTest"
  key_links:
    - from: "pending_migrations_verifier.rb"
      to: "REQ-27"
      via: "Checks for unmigrated SourceMonitor migrations without running them"
    - from: "upgrade_command.rb"
      to: "REQ-26"
      via: "Detects version changes, copies migrations, re-runs generator, runs verification"
    - from: "cli.rb#upgrade"
      to: "upgrade_command.rb"
      via: "CLI dispatches upgrade subcommand to UpgradeCommand"
    - from: "runner.rb#default_verifiers"
      to: "pending_migrations_verifier.rb"
      via: "Runner includes PendingMigrationsVerifier in the default verifier set"
---
<objective>
Add a PendingMigrationsVerifier to the verification suite (REQ-27) and a `bin/source_monitor upgrade` command (REQ-26) that detects version changes since last install, copies new migrations, re-runs the idempotent generator, runs verification, and reports what changed. The upgrade command stores a `.source_monitor_version` file marker in the host app root.
</objective>
<context>
@lib/source_monitor/setup/verification/solid_queue_verifier.rb -- Primary pattern reference for the new PendingMigrationsVerifier. Shows constructor dependency injection (process_relation:, connection:, clock:), `call` method with guard clauses returning early for missing deps, and Result helpers (ok_result, warning_result, error_result). Key: each verifier returns a single Result. The PendingMigrationsVerifier should follow this exact structure.

@lib/source_monitor/setup/verification/recurring_schedule_verifier.rb -- Second pattern reference. Shows how to query a relation and filter results. The PendingMigrationsVerifier needs a different approach: it must compare engine migration files against the host app's `db/migrate/` directory to find migrations that have been copied but not yet run (pending), or that have not been copied at all (missing).

@lib/source_monitor/setup/verification/result.rb -- Result struct with key, name, status, details, remediation and status predicates (ok?, warning?, error?). Summary aggregates results. The PendingMigrationsVerifier should use key: :pending_migrations, name: "Pending Migrations".

@lib/source_monitor/setup/verification/runner.rb -- Orchestrator with `default_verifiers` array. Currently `[SolidQueueVerifier.new, RecurringScheduleVerifier.new, ActionCableVerifier.new]`. Add `PendingMigrationsVerifier.new` to this array, placed first since migration status is the most fundamental check.

@lib/source_monitor/setup/cli.rb -- Thor-based CLI with `install` and `verify` subcommands. The `upgrade` subcommand follows the same pattern: instantiate UpgradeCommand, call it, handle the summary via handle_summary. Thor handles command dispatch automatically.

@lib/source_monitor/setup/workflow.rb -- The install workflow that the upgrade command partially re-uses. Key collaborators: MigrationInstaller (copies + runs migrations), InstallGenerator (idempotent generator), Verification::Runner (runs all verifiers). The upgrade command orchestrates a subset of these: migration_installer.install, install_generator.run, verification_runner.call.

@lib/source_monitor/setup/migration_installer.rb -- Copies engine migrations via `bin/rails railties:install:migrations FROM=source_monitor`, deduplicates Solid Queue migrations, then runs `db:migrate`. The upgrade command delegates to this directly.

@lib/source_monitor/setup/install_generator.rb -- Wraps `bin/rails generate source_monitor:install --mount-path=...`. Fully idempotent, safe to re-run. The upgrade command calls this to pick up any new generator steps added in the new version.

@test/lib/source_monitor/setup/verification/solid_queue_verifier_test.rb -- Test pattern: FakeRelation and FakeConnection stubs, tests all branches. The PendingMigrationsVerifier test should use similar lightweight stubs.

@test/lib/source_monitor/setup/cli_test.rb -- Tests CLI commands by stubbing collaborators. The upgrade command test should follow the same Minitest::Mock + stub pattern.

@test/lib/source_monitor/setup/verification/runner_test.rb -- Tests Runner with stub verifiers. Must be updated to include PendingMigrationsVerifier in the default verifiers test (expect 4 results instead of 3).

@test/lib/source_monitor/setup/migration_installer_test.rb -- Shows FakeShell pattern for testing shell commands. The UpgradeCommand test should use the same approach.

@lib/source_monitor.rb lines 157-184 -- Autoload declarations for Setup module and Verification submodule. Add `autoload :UpgradeCommand` in Setup block and `autoload :PendingMigrationsVerifier` in Verification block.

@lib/source_monitor/version.rb -- VERSION constant ("0.4.0"). The upgrade command compares this against the stored `.source_monitor_version` marker file.

**Version marker design decision:** Use a plain text file `.source_monitor_version` in the host app root (Dir.pwd). This is the simplest approach: no database dependency, no migration needed, easy to inspect and debug. The file contains the gem version string (e.g., "0.4.0"). The upgrade command reads this file, compares to SourceMonitor::VERSION, and acts accordingly. If the file does not exist, the upgrade command treats it as a fresh install scenario and runs the full upgrade flow.

**PendingMigrationsVerifier design:** The verifier checks whether engine migrations have been copied to the host app and whether any are pending (not yet run). It uses `bin/rails railties:install:migrations FROM=source_monitor --dry-run` or compares engine migration filenames against `db/migrate/`. A simpler approach: compare the engine's `db/migrate/` files against the host's `db/migrate/` files by migration name (ignoring timestamps). If engine migrations are missing from the host, report them. This check does NOT run migrations -- that is the upgrade command's job.

**Simpler PendingMigrationsVerifier approach:** Inject the engine migrations path and host migrations path. Compare migration basenames (strip timestamps). Any engine migration whose basename is not found in the host's db/migrate/ is "missing". For "pending" (copied but not run), check ActiveRecord::Base.connection.migration_context.needs_migration? -- but this checks ALL migrations, not just SourceMonitor ones. A pragmatic middle ground: check if any engine migration names are missing from the host, and separately check if the overall schema needs migration. If engine migrations are all present and no pending migrations exist, report ok. If engine migrations are missing, report warning with list of missing migration names.
</context>
<tasks>
<task type="auto">
  <name>create-pending-migrations-verifier</name>
  <files>
    lib/source_monitor/setup/verification/pending_migrations_verifier.rb
  </files>
  <action>
Create `lib/source_monitor/setup/verification/pending_migrations_verifier.rb` following the verifier pattern from SolidQueueVerifier and RecurringScheduleVerifier.

The verifier checks two things:
1. Whether all engine migrations have been copied to the host app's `db/migrate/` directory
2. Whether there are any pending migrations (copied but not run)

Constructor accepts dependency-injected parameters for testability:
- `engine_migrations_path:` -- defaults to the engine's `db/migrate/` directory (SourceMonitor::Engine.root.join("db/migrate"))
- `host_migrations_path:` -- defaults to `Rails.root.join("db/migrate")`
- `connection:` -- defaults to `ActiveRecord::Base.connection`

The `call` method logic:
1. List engine migration files, extract basenames without timestamps (e.g., `create_source_monitor_sources` from `20241008120000_create_source_monitor_sources.rb`). Filter to only `source_monitor` migrations (basename contains "source_monitor" or "solid_cable" or "solid_queue"). Actually, simpler: only check migrations whose basename contains `source_monitor`.
2. List host migration files, extract basenames the same way.
3. Find missing: engine basenames not present in host basenames.
4. If missing migrations exist: return warning_result listing missing migration names with remediation to run `bin/source_monitor upgrade` or `bin/rails railties:install:migrations FROM=source_monitor`.
5. If all present, check `connection.migration_context.needs_migration?` -- if true, return warning_result that migrations are pending.
6. If all present and no pending: return ok_result.
7. Wrap in rescue StandardError for unexpected failures.

Use key: `:pending_migrations`, name: `"Pending Migrations"`.

Filter engine migrations to only those whose basename includes "source_monitor" (skip solid_queue and solid_cable migrations since those are owned by their respective engines). This ensures the verifier only checks SourceMonitor's own tables.
  </action>
  <verify>
Read the created file. Confirm: (a) class is in correct module nesting `SourceMonitor::Setup::Verification::PendingMigrationsVerifier`, (b) constructor injects `engine_migrations_path:`, `host_migrations_path:`, `connection:`, (c) `call` handles: all present + migrated (ok), missing migrations (warning), pending migrations (warning), unexpected error, (d) Result key is `:pending_migrations`, (e) only checks `source_monitor` migrations.
  </verify>
  <done>
PendingMigrationsVerifier created with all branches: ok (all present, none pending), warning (missing migrations), warning (pending migrations), error (unexpected failure). Only checks source_monitor-prefixed migrations.
  </done>
</task>
<task type="auto">
  <name>add-pending-migrations-verifier-tests</name>
  <files>
    test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb
  </files>
  <action>
Create `test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb` following the test patterns from `solid_queue_verifier_test.rb`.

Use `Dir.mktmpdir` to create temporary directories representing engine and host migration paths, then populate them with fake migration files to test each branch.

Tests to write:

1. **"returns ok when all engine migrations are present and none pending"** -- Create engine dir with `20241008120000_create_source_monitor_sources.rb` and `20241008121000_create_source_monitor_items.rb`. Create host dir with same basenames (different timestamps ok). Stub connection so `migration_context.needs_migration?` returns false. Assert status :ok.

2. **"warns when engine migrations are missing from host"** -- Create engine dir with two source_monitor migrations. Create host dir with only one. Assert status :warning. Assert details mention the missing migration basename.

3. **"warns when migrations are pending"** -- All engine migrations present in host. Stub `migration_context.needs_migration?` to return true. Assert status :warning with remediation mentioning `db:migrate`.

4. **"ignores non-source-monitor engine migrations"** -- Engine dir has `20251010160000_create_solid_cable_messages.rb` (not a source_monitor migration). Host dir is empty. Assert status :ok (no source_monitor migrations missing).

5. **"rescues unexpected failures"** -- Pass a connection that raises on `migration_context`. Assert status :error with remediation.

Use lightweight stubs:
```ruby
class FakeMigrationContext
  def initialize(needs_migration:)
    @needs_migration = needs_migration
  end
  def needs_migration?
    @needs_migration
  end
end

class FakeConnection
  def initialize(needs_migration: false)
    @context = FakeMigrationContext.new(needs_migration: needs_migration)
  end
  def migration_context
    @context
  end
end
```

5 tests covering all branches.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb` -- all 5 tests pass. Run `bin/rubocop test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb` -- 0 offenses.
  </verify>
  <done>
5 tests pass covering: ok (all present, not pending), warning (missing), warning (pending), ok (ignores non-SM migrations), error (unexpected failure). RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>wire-verifier-into-runner-and-autoload</name>
  <files>
    lib/source_monitor/setup/verification/runner.rb
    lib/source_monitor.rb
    test/lib/source_monitor/setup/verification/runner_test.rb
  </files>
  <action>
**Modify `lib/source_monitor/setup/verification/runner.rb`:**

Add `PendingMigrationsVerifier.new` as the FIRST entry in the `default_verifiers` array. Migration status is the most fundamental check and should run before other verifiers. The array becomes:
```ruby
def default_verifiers
  [ PendingMigrationsVerifier.new, SolidQueueVerifier.new, RecurringScheduleVerifier.new, ActionCableVerifier.new ]
end
```

**Modify `lib/source_monitor.rb`:**

Add the autoload declaration in the `module Verification` block (around line 177), before the Runner line:
```ruby
autoload :PendingMigrationsVerifier, "source_monitor/setup/verification/pending_migrations_verifier"
```

Also add in the `module Setup` block (around line 171):
```ruby
autoload :UpgradeCommand, "source_monitor/setup/upgrade_command"
```
(This autoload is needed for task 4 but adding it here keeps autoload changes in one task.)

**Modify `test/lib/source_monitor/setup/verification/runner_test.rb`:**

Update the "uses default verifiers" test:
1. Add `pending_result = Result.new(key: :pending_migrations, name: "Pending Migrations", status: :ok, details: "ok")`
2. Add `pending_double = verifier_double.new(pending_result)`
3. Add a stub for `PendingMigrationsVerifier.stub(:new, ->(*) { pending_double })` wrapping the existing stubs
4. Update assertion to `assert_equal 4, summary.results.size`
5. Add `assert_equal 1, pending_double.calls`
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` -- all tests pass. Grep for `PendingMigrationsVerifier` in runner.rb and source_monitor.rb confirms wiring. Grep for `UpgradeCommand` in source_monitor.rb confirms autoload.
  </verify>
  <done>
PendingMigrationsVerifier wired into Runner.default_verifiers as the first verifier. Both PendingMigrationsVerifier and UpgradeCommand autoloaded from lib/source_monitor.rb. Runner test updated to expect 4 verifiers.
  </done>
</task>
<task type="auto">
  <name>create-upgrade-command-and-cli-integration</name>
  <files>
    lib/source_monitor/setup/upgrade_command.rb
    lib/source_monitor/setup/cli.rb
  </files>
  <action>
**Create `lib/source_monitor/setup/upgrade_command.rb`:**

The UpgradeCommand orchestrates the upgrade flow. Constructor accepts dependency-injected collaborators for testability:
- `migration_installer:` -- defaults to `MigrationInstaller.new`
- `install_generator:` -- defaults to `InstallGenerator.new`
- `verifier:` -- defaults to `Verification::Runner.new`
- `version_file:` -- defaults to `File.join(Dir.pwd, ".source_monitor_version")`
- `current_version:` -- defaults to `SourceMonitor::VERSION`

Public method `call` returns a `Verification::Summary`:

```ruby
def call
  stored = read_stored_version
  if stored == current_version
    return up_to_date_summary
  end

  migration_installer.install
  install_generator.run
  summary = verifier.call
  write_version_marker
  summary
end
```

Private methods:
- `read_stored_version` -- reads `.source_monitor_version` file, returns nil if missing, strips whitespace
- `write_version_marker` -- writes `current_version` to the version file
- `up_to_date_summary` -- returns a `Verification::Summary` with a single ok Result: key `:upgrade`, name `"Upgrade"`, details `"Already up to date (v#{current_version})"`, no remediation

Key design points:
- The command is intentionally simple: it orchestrates existing tools
- MigrationInstaller handles copying + deduplication + running migrations
- InstallGenerator re-runs the idempotent generator to pick up new steps
- Verification::Runner runs all verifiers (including PendingMigrationsVerifier) to confirm health
- Version marker is written AFTER successful verification so a failed upgrade can be re-run
- The `up_to_date_summary` returns an ok summary so `handle_summary` does not exit(1)

**Modify `lib/source_monitor/setup/cli.rb`:**

Add an `upgrade` subcommand following the pattern of `install` and `verify`:

```ruby
desc "upgrade", "Upgrade SourceMonitor after a gem version change"
def upgrade
  command = UpgradeCommand.new
  summary = command.call
  handle_summary(summary)
end
```

Place it after the `verify` method, before the `private` keyword.
  </action>
  <verify>
Read `lib/source_monitor/setup/upgrade_command.rb` and confirm: (a) constructor accepts all 5 injectable deps, (b) `call` checks version marker, returns early if current, otherwise runs migration_installer + install_generator + verifier, (c) writes version marker after verification, (d) up_to_date_summary returns ok. Read `lib/source_monitor/setup/cli.rb` and confirm the `upgrade` method exists and delegates to UpgradeCommand.
  </verify>
  <done>
UpgradeCommand created with version detection and orchestration of MigrationInstaller, InstallGenerator, and Verification::Runner. CLI wired with `upgrade` subcommand. Version marker stored in `.source_monitor_version`.
  </done>
</task>
<task type="auto">
  <name>upgrade-command-tests-and-full-verification</name>
  <files>
    test/lib/source_monitor/setup/upgrade_command_test.rb
    test/lib/source_monitor/setup/cli_test.rb
  </files>
  <action>
**Create `test/lib/source_monitor/setup/upgrade_command_test.rb`:**

Follow the test patterns from `workflow_test.rb` and `migration_installer_test.rb`. Use `Dir.mktmpdir` for the version file location. Use Minitest::Mock for collaborators.

Tests to write:

1. **"returns up-to-date summary when version matches"** -- Create a tmpdir, write "0.4.0" to version file. Instantiate UpgradeCommand with version_file pointing there, current_version "0.4.0". Call. Assert summary is ok with details matching "Already up to date". Assert migration_installer, install_generator, verifier were NOT called (use mocks that would fail if called).

2. **"runs upgrade flow when version differs"** -- Write "0.3.3" to version file. Create mocks for migration_installer (expect :install), install_generator (expect :run), verifier (expect :call, returns ok Summary). Call. Verify all mocks called. Assert version file now contains "0.4.0".

3. **"runs upgrade flow when version file missing"** -- No version file exists. Same mock setup as test 2. Call. Verify all mocks called. Assert version file created with "0.4.0".

4. **"does not write version marker until after verification"** -- Verifier raises an error. Assert version file is NOT updated (still contains old version or does not exist). Use a verifier that raises to simulate failure.

5. **"version marker file is plain text with version string"** -- After successful upgrade, read the file and assert it equals the version string with no extra whitespace.

**Modify `test/lib/source_monitor/setup/cli_test.rb`:**

Add a test for the upgrade command following the same pattern as the existing "verify command runs runner" test:

```ruby
test "upgrade command delegates to upgrade command and prints summary" do
  summary = SourceMonitor::Setup::Verification::Summary.new([])
  upgrade_cmd = Minitest::Mock.new
  upgrade_cmd.expect(:call, summary)
  printer = Minitest::Mock.new
  printer.expect(:print, nil, [summary])

  SourceMonitor::Setup::UpgradeCommand.stub(:new, ->(*) { upgrade_cmd }) do
    SourceMonitor::Setup::Verification::Printer.stub(:new, printer) do
      CLI.start(["upgrade"])
    end
  end

  upgrade_cmd.verify
  printer.verify
  assert_mock upgrade_cmd
  assert_mock printer
end
```

**Run full verification:**
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/upgrade_command_test.rb` -- all tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/cli_test.rb` -- all tests pass
3. `bin/rails test` -- full suite passes with 973+ runs and 0 failures
4. `bin/rubocop` -- zero offenses
5. `bin/brakeman --no-pager` -- zero warnings
  </action>
  <verify>
`PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/upgrade_command_test.rb` exits 0. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/cli_test.rb` exits 0. `bin/rails test` exits 0 with 973+ runs, 0 failures. `bin/rubocop` exits 0. `bin/brakeman --no-pager` exits 0.
  </verify>
  <done>
5 UpgradeCommand tests + 1 CLI test pass. Full suite green. RuboCop clean. Brakeman clean. All REQ-26 and REQ-27 acceptance criteria met.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb` -- 5 tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/verification/runner_test.rb` -- 2 tests pass with 4-verifier expectation
3. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/upgrade_command_test.rb` -- 5 tests pass
4. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/cli_test.rb` -- 5 tests pass (4 existing + 1 new)
5. `bin/rails test` -- 973+ runs, 0 failures
6. `bin/rubocop` -- 0 offenses
7. `bin/brakeman --no-pager` -- 0 warnings
8. `grep -n 'class PendingMigrationsVerifier' lib/source_monitor/setup/verification/pending_migrations_verifier.rb` returns a match
9. `grep -n 'class UpgradeCommand' lib/source_monitor/setup/upgrade_command.rb` returns a match
10. `grep -n 'def upgrade' lib/source_monitor/setup/cli.rb` returns a match
11. `grep -n 'PendingMigrationsVerifier' lib/source_monitor/setup/verification/runner.rb` returns a match
12. `grep -n 'PendingMigrationsVerifier' lib/source_monitor.rb` returns a match
13. `grep -n 'UpgradeCommand' lib/source_monitor.rb` returns a match
14. `grep -n '.source_monitor_version' lib/source_monitor/setup/upgrade_command.rb` returns a match
</verification>
<success_criteria>
- PendingMigrationsVerifier returns ok when all SourceMonitor migrations are present and run (REQ-27)
- PendingMigrationsVerifier warns when engine migrations are missing from host (REQ-27)
- PendingMigrationsVerifier warns when migrations are pending (copied but not run) (REQ-27)
- PendingMigrationsVerifier ignores non-SourceMonitor engine migrations (REQ-27)
- PendingMigrationsVerifier is included in Runner.default_verifiers (REQ-27)
- UpgradeCommand compares stored .source_monitor_version against SourceMonitor::VERSION (REQ-26)
- UpgradeCommand returns "Already up to date" when versions match (REQ-26)
- UpgradeCommand copies migrations, re-runs generator, runs verification when versions differ (REQ-26)
- UpgradeCommand writes version marker only after successful verification (REQ-26)
- `bin/source_monitor upgrade` CLI subcommand dispatches to UpgradeCommand (REQ-26)
- Both PendingMigrationsVerifier and UpgradeCommand autoloaded from lib/source_monitor.rb
- All existing tests continue to pass (no regressions)
- 11+ new tests across PendingMigrationsVerifier, UpgradeCommand, and CLI
- RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/01-upgrade-command/PLAN-01-SUMMARY.md
</output>
