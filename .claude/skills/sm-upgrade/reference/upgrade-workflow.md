# Upgrade Workflow Reference

Detailed step-by-step reference for AI agents guiding host app developers through SourceMonitor gem upgrades.

## Pre-Upgrade Checklist

1. Identify current version: `grep source_monitor Gemfile.lock` or `cat .source_monitor_version`
2. Identify target version: check RubyGems or GitHub releases
3. Read CHANGELOG.md between those versions (in gem source: `bundle show source_monitor` to find gem path, then read CHANGELOG.md)
4. Note any breaking changes, removed options, or new required configuration

## CHANGELOG Parsing Guide

- Format: [Keep a Changelog](https://keepachangelog.com)
- Each version has a `## [X.Y.Z] - YYYY-MM-DD` header
- Subsections: Added, Changed, Fixed, Removed, Deprecated, Security
- For multi-version jumps, read ALL sections between current and target
- Key things to flag:
  - **Removed** entries -- breaking changes, must address before upgrading
  - **Changed** entries -- behavioral changes, review for impact
  - **Deprecated** entries -- action needed now or in a future version
- Example: To upgrade from 0.3.1 to 0.4.0, read sections [0.3.2], [0.3.3], and [0.4.0]

## Upgrade Command Internals

How `bin/source_monitor upgrade` works internally:

1. Reads `.source_monitor_version` from host app root (nil if first run)
2. Compares stored version against `SourceMonitor::VERSION` (current gem version)
3. If same: returns "Already up to date" with exit 0
4. If different:
   a. `MigrationInstaller.install` -- copies new engine migrations to `db/migrate/`
   b. `InstallGenerator.run` -- re-runs the install generator (idempotent: skips existing routes, initializer, etc.)
   c. `Verification::Runner.call` -- runs all 4 verifiers
   d. Writes current version to `.source_monitor_version`
5. Prints verification summary and exits (0 = all OK, 1 = any failure)

Source: `lib/source_monitor/setup/upgrade_command.rb`

## Post-Upgrade Verification

The verification runner (`lib/source_monitor/setup/verification/runner.rb`) executes 4 verifiers in sequence:

### PendingMigrationsVerifier

Checks that all SourceMonitor migrations in the gem have corresponding files in host `db/migrate/`. Warns if any are missing or not yet run.

**Fix:** `bin/rails db:migrate`

### SolidQueueVerifier

Checks that Solid Queue workers are running. Provides remediation guidance mentioning `Procfile.dev` for `bin/dev` users.

**Fix:** Start workers via `bin/rails solid_queue:start` or ensure `Procfile.dev` has a `jobs:` entry.

### RecurringScheduleVerifier

Checks that SourceMonitor recurring tasks (ScheduleFetchesJob, scrape scheduling, cleanup jobs) are registered in Solid Queue. Verifies that `config/recurring.yml` exists and `config/queue.yml` dispatchers have `recurring_schedule: config/recurring.yml`.

**Fix:** Re-run `bin/rails generate source_monitor:install` to patch `config/queue.yml` and create `config/recurring.yml`.

### ActionCableVerifier

Checks that Action Cable is configured with a production-ready adapter (Solid Cable or Redis). Development mode uses async adapter by default, which is not suitable for production.

**Fix:** Add `solid_cable` gem or configure Redis adapter in `config/cable.yml`.

## Troubleshooting Common Upgrade Issues

### "Already up to date" but expected changes

- Check that `bundle update source_monitor` actually pulled the new version
- Verify `Gemfile.lock` shows the expected version: `grep source_monitor Gemfile.lock`
- If the `.source_monitor_version` marker was manually edited, delete it and re-run `bin/source_monitor upgrade`

### Migrations fail

- Check for conflicting migration timestamps
- Remove duplicate migration files from `db/migrate/` (keep the newer one)
- Re-run `bin/rails db:migrate`

### Deprecation errors at boot

- Option was removed (`:error` severity)
- Read the error message for the replacement option path
- Update `config/initializers/source_monitor.rb` before restarting
- Consult `docs/configuration.md` if unsure which option to use

### Generator fails

- Usually safe to re-run manually: `bin/rails generate source_monitor:install`
- The generator is idempotent -- it skips existing routes, initializer, and config entries
