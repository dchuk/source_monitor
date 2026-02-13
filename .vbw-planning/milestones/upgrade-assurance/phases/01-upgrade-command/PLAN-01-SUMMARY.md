---
phase: 1
plan: "01"
title: upgrade-command-and-migration-verifier
status: complete
---

## Tasks
- [x] Task 1: create-pending-migrations-verifier
- [x] Task 2: add-pending-migrations-verifier-tests
- [x] Task 3: wire-verifier-into-runner-and-autoload
- [x] Task 4: create-upgrade-command-and-cli-integration
- [x] Task 5: upgrade-command-tests-and-full-verification

## Commits
- 980650b feat(01-upgrade-command): create-pending-migrations-verifier
- 3834f50 test(01-upgrade-command): add-pending-migrations-verifier-tests
- 9fbccf5 feat(01-upgrade-command): wire-verifier-into-runner-and-autoload
- 67f190d feat(01-upgrade-command): create-upgrade-command-and-cli-integration
- a766f6f test(01-upgrade-command): upgrade-command-tests-and-full-verification

## What Was Built
- PendingMigrationsVerifier (REQ-27): checks engine migrations presence in host db/migrate, warns on missing or pending, filters to source_monitor-only migrations
- UpgradeCommand (REQ-26): compares .source_monitor_version marker against VERSION, orchestrates MigrationInstaller + InstallGenerator + Verification::Runner, writes marker only after success
- CLI upgrade subcommand: dispatches to UpgradeCommand via handle_summary
- Runner wiring: PendingMigrationsVerifier added as first default verifier (most fundamental check)
- Autoloads: PendingMigrationsVerifier in Verification module, UpgradeCommand in Setup module
- 11 new tests: 5 verifier + 5 upgrade command + 1 CLI upgrade
- Full suite: 992 runs, 0 failures, RuboCop 0 offenses, Brakeman 0 warnings

## Files Modified
- lib/source_monitor/setup/verification/pending_migrations_verifier.rb (new)
- lib/source_monitor/setup/upgrade_command.rb (new)
- lib/source_monitor/setup/cli.rb (upgrade subcommand)
- lib/source_monitor/setup/verification/runner.rb (PendingMigrationsVerifier in default_verifiers)
- lib/source_monitor.rb (autoload declarations)
- test/lib/source_monitor/setup/verification/pending_migrations_verifier_test.rb (new, 5 tests)
- test/lib/source_monitor/setup/upgrade_command_test.rb (new, 5 tests)
- test/lib/source_monitor/setup/verification/runner_test.rb (4-verifier expectation)
- test/lib/source_monitor/setup/cli_test.rb (upgrade CLI test)

## Deviations
- None
