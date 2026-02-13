---
name: sm-upgrade
description: Use when upgrading SourceMonitor to a new gem version, including CHANGELOG review, running the upgrade command, interpreting verification results, and handling configuration deprecations.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-upgrade: Gem Upgrade Workflow

Guides AI agents through upgrading SourceMonitor in a host Rails application after a new gem version is released. Covers CHANGELOG review, running the upgrade command, interpreting verification results, handling deprecation warnings, and resolving common edge cases.

## When to Use

- Host app is updating the source_monitor gem version in Gemfile
- User reports deprecation warnings after a gem update
- User wants to know what changed between versions
- Troubleshooting a broken upgrade
- Migrating configuration after breaking changes

## Prerequisites

| Requirement | How to Check |
|---|---|
| Existing SourceMonitor installation | `cat .source_monitor_version` or check `config/initializers/source_monitor.rb` |
| Access to CHANGELOG.md | Bundled with gem: `bundle show source_monitor` then read CHANGELOG.md |
| Current gem version known | `grep source_monitor Gemfile.lock` |

## Upgrade Workflow

1. **Review CHANGELOG** -- Read `CHANGELOG.md` in the gem source. Identify changes between the current installed version (from `.source_monitor_version` or `Gemfile.lock`) and the target version. Focus on Added, Changed, Fixed, Removed sections. Flag any breaking changes or deprecation notices.
2. **Update Gemfile** -- Bump the version constraint in the host app's Gemfile: `gem "source_monitor", "~> X.Y"`. Run `bundle update source_monitor`.
3. **Run the upgrade command** -- `bin/source_monitor upgrade`. This automatically: detects the version change via `.source_monitor_version` marker, copies new migrations, re-runs the install generator (idempotent), runs the full verification suite.
4. **Run database migrations** -- `bin/rails db:migrate` if the upgrade command copied new migrations.
5. **Handle deprecation warnings** -- If the configure block in the initializer uses deprecated options, Rails logger will show warnings at boot. Read each warning, identify the replacement, update the initializer. See `sm-configure` skill for configuration reference.
6. **Run verification** -- `bin/source_monitor verify` to confirm all checks pass.
7. **Restart processes** -- Restart web server and Solid Queue workers to pick up the new version.

## Interpreting Upgrade Results

The upgrade command runs 4 verification checks automatically:

| Check | OK | Failure | Fix |
|---|---|---|---|
| PendingMigrations | All engine migrations present | Missing migrations need copying | `bin/rails db:migrate` |
| SolidQueue | Workers running | Workers not detected | Start Solid Queue workers via `Procfile.dev` or `bin/rails solid_queue:start` |
| RecurringSchedule | Tasks registered | Tasks missing from dispatcher | Re-run generator or check `config/queue.yml` |
| ActionCable | Adapter configured | No production adapter | Configure Solid Cable or Redis adapter |

## Handling Deprecation Warnings

The deprecation framework uses two severity levels:

- **`:warning`** -- Option renamed. The old name still works but logs a deprecation message. Update the initializer to use the new option name. The message includes the replacement path.
- **`:error`** -- Option removed. Using the old name raises `SourceMonitor::DeprecatedOptionError`. You must remove or replace the option before the app can boot.

Pattern for fixing deprecations:

1. Read the deprecation message (logged to `Rails.logger` or raised as an error)
2. Find the replacement option path in the message
3. Update `config/initializers/source_monitor.rb`
4. Restart and verify the warning is gone

Example deprecation message:
```
[SourceMonitor] DEPRECATION: 'http.old_option' was deprecated in v0.5.0 and replaced by 'http.new_option'.
```

## Edge Cases

- **First install (no `.source_monitor_version` file):** Upgrade command treats this as a version change and runs the full workflow. Safe to run on first install.
- **Same version (no change):** Command reports "Already up to date (vX.Y.Z)" and exits cleanly.
- **Skipped versions (e.g., 0.2.0 to 0.4.0):** Read all CHANGELOG sections between the two versions. Multiple migrations may need running.
- **Failed verification after upgrade:** Read the verification output. Most common: pending migrations (run `db:migrate`), missing Solid Queue workers (start workers), stale recurring schedule (re-run generator).
- **Custom scrapers or event handlers:** Check CHANGELOG for API changes in `Scrapers::Base` or event callback signatures.

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/setup/upgrade_command.rb` | Upgrade orchestrator |
| `lib/source_monitor/setup/cli.rb` | CLI entry point (`bin/source_monitor upgrade`) |
| `lib/source_monitor/setup/verification/runner.rb` | Verification runner (4 verifiers) |
| `lib/source_monitor/configuration/deprecation_registry.rb` | Deprecation framework |
| `CHANGELOG.md` | Version history (Keep a Changelog format) |
| `.source_monitor_version` | Version marker in host app root |

## References

- `docs/upgrade.md` -- Human-readable upgrade guide
- `docs/setup.md` -- Initial setup documentation
- `docs/troubleshooting.md` -- Common issues and fixes
- `sm-host-setup` skill -- Initial installation workflow
- `sm-configure` skill -- Configuration reference for updating deprecated options

## Checklist

- [ ] CHANGELOG reviewed for version range
- [ ] Gemfile updated and `bundle update source_monitor` run
- [ ] `bin/source_monitor upgrade` completed successfully
- [ ] Database migrations applied if needed
- [ ] Deprecation warnings addressed in initializer
- [ ] `bin/source_monitor verify` passes all checks
- [ ] Web server and workers restarted
