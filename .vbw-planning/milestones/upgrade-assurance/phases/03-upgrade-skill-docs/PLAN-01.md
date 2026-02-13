---
phase: 3
plan: "01"
title: upgrade-skill-and-documentation
type: execute
wave: 1
depends_on: []
cross_phase_deps:
  - {phase: 1, plan: "01", artifact: "lib/source_monitor/setup/upgrade_command.rb", reason: "Skill documents the upgrade command workflow"}
  - {phase: 1, plan: "01", artifact: "lib/source_monitor/setup/verification/runner.rb", reason: "Skill references verification suite"}
  - {phase: 1, plan: "01", artifact: "lib/source_monitor/setup/cli.rb", reason: "Skill references CLI entry point"}
  - {phase: 2, plan: "01", artifact: "lib/source_monitor/configuration/deprecation_registry.rb", reason: "Skill covers deprecation warnings in upgrade flow"}
autonomous: true
effort_override: thorough
skills_used: [sm-host-setup]
files_modified:
  - .claude/skills/sm-upgrade/SKILL.md
  - .claude/skills/sm-upgrade/reference/upgrade-workflow.md
  - .claude/skills/sm-upgrade/reference/version-history.md
  - docs/upgrade.md
  - .claude/skills/sm-host-setup/SKILL.md
  - lib/source_monitor/setup/skills_installer.rb
  - test/lib/source_monitor/setup/skills_installer_test.rb
  - CLAUDE.md
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/skills_installer_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/setup/skills_installer.rb` exits 0 with no offenses"
    - "Running `bin/rails test` exits 0 with 1002+ runs and 0 failures"
    - "Running `bin/rubocop` exits 0 with no offenses"
    - "`grep -r 'sm-upgrade' lib/source_monitor/setup/skills_installer.rb` returns a match in CONSUMER_SKILLS"
    - "`grep -r 'sm-upgrade' CLAUDE.md` returns a match in Consumer Skills table"
  artifacts:
    - path: ".claude/skills/sm-upgrade/SKILL.md"
      provides: "AI skill guide for gem upgrade workflows (REQ-29)"
      contains: "sm-upgrade"
    - path: ".claude/skills/sm-upgrade/reference/upgrade-workflow.md"
      provides: "Step-by-step upgrade workflow with CHANGELOG parsing and edge cases"
      contains: "bin/source_monitor upgrade"
    - path: ".claude/skills/sm-upgrade/reference/version-history.md"
      provides: "Version-specific upgrade notes for agents to reference"
      contains: "0.3.x"
    - path: "docs/upgrade.md"
      provides: "Human-readable upgrade guide with version-specific instructions (REQ-30)"
      contains: "Upgrade Guide"
    - path: ".claude/skills/sm-host-setup/SKILL.md"
      provides: "Updated host setup skill with cross-reference to upgrade flow"
      contains: "sm-upgrade"
    - path: "lib/source_monitor/setup/skills_installer.rb"
      provides: "Skills installer updated with sm-upgrade in CONSUMER_SKILLS"
      contains: "sm-upgrade"
    - path: "test/lib/source_monitor/setup/skills_installer_test.rb"
      provides: "Tests still pass with updated CONSUMER_SKILLS constant"
      contains: "sm-upgrade"
    - path: "CLAUDE.md"
      provides: "Updated skill catalog listing sm-upgrade"
      contains: "sm-upgrade"
  key_links:
    - from: "SKILL.md"
      to: "REQ-29"
      via: "Skill covers CHANGELOG parsing, running upgrade command, interpreting results, handling edge cases"
    - from: "docs/upgrade.md"
      to: "REQ-30"
      via: "Versioned upgrade guide with general steps, 0.3.x to 0.4.x notes, troubleshooting"
    - from: "SKILL.md"
      to: "upgrade_command.rb"
      via: "Skill references the upgrade command as the primary tool"
    - from: "SKILL.md"
      to: "deprecation_registry.rb"
      via: "Skill covers interpreting deprecation warnings during upgrade"
    - from: "sm-host-setup/SKILL.md"
      to: "SKILL.md"
      via: "Host setup skill cross-references sm-upgrade for post-install upgrades"
    - from: "skills_installer.rb"
      to: "SKILL.md"
      via: "Installer distributes sm-upgrade as a consumer skill to host apps"
---
<objective>
Create the `sm-upgrade` AI skill (REQ-29) and `docs/upgrade.md` human upgrade guide (REQ-30), then wire the skill into the skills installer as a consumer skill. The sm-upgrade skill teaches AI agents how to guide host app developers through gem updates -- reading the CHANGELOG between versions, running `bin/source_monitor upgrade`, interpreting verification results, and handling deprecation warnings and edge cases. The docs/upgrade.md provides the same guidance in human-readable form with version-specific migration notes (0.3.x to 0.4.x, 0.4.x to current). Update sm-host-setup to cross-reference the upgrade flow, and update CLAUDE.md to list the new skill.
</objective>
<context>
@lib/source_monitor/setup/upgrade_command.rb -- The upgrade command orchestrator built in Phase 1. It compares the stored `.source_monitor_version` marker against `SourceMonitor::VERSION`, and if different: runs MigrationInstaller, re-runs InstallGenerator, runs Verification::Runner, then writes the new version marker. If same: returns "Already up to date" summary. The skill must document this full workflow and what each step does, so agents can explain outputs to users.

@lib/source_monitor/setup/cli.rb -- The Thor CLI that provides `bin/source_monitor upgrade` as the entry point. Also provides `install` and `verify` subcommands. The skill should reference all three commands in context (upgrade is primary, verify for post-upgrade checks, install for first-time setup).

@lib/source_monitor/setup/verification/runner.rb -- Runs 4 verifiers in sequence: PendingMigrationsVerifier, SolidQueueVerifier, RecurringScheduleVerifier, ActionCableVerifier. The upgrade command calls this automatically. The skill should explain what each verifier checks and how to interpret failures.

@lib/source_monitor/configuration/deprecation_registry.rb -- The deprecation framework built in Phase 2. When host apps upgrade and their initializer uses deprecated config options, they get :warning or :error messages. The skill must cover how to handle these: read the deprecation message, find the replacement option, update the initializer, re-run configure.

@CHANGELOG.md -- Keep a Changelog format with version sections. The skill should teach agents to parse this file to identify what changed between the user's current version and the target version. Each version section has Added/Changed/Fixed/Removed subsections.

@.claude/skills/sm-host-setup/SKILL.md -- Existing consumer skill for initial setup. Has a "When to Use" section that includes "Re-running setup after upgrading the gem" -- this should be updated to reference the sm-upgrade skill instead. Add a cross-reference in the References section pointing to sm-upgrade for upgrade workflows.

@lib/source_monitor/setup/skills_installer.rb -- The installer that copies sm-* skills to host apps. CONSUMER_SKILLS constant must include "sm-upgrade". The test file creates fake skills for each entry in CONSUMER_SKILLS, so updating the constant means the test will automatically include sm-upgrade in its assertions.

@test/lib/source_monitor/setup/skills_installer_test.rb -- Tests for the skills installer. Tests iterate CONSUMER_SKILLS and CONTRIBUTOR_SKILLS constants. Adding sm-upgrade to CONSUMER_SKILLS is enough -- existing test assertions use the constants dynamically. However, the first test "install defaults to consumer group" hardcodes specific skill names ("sm-dashboard-widget", "sm-host-setup") and should NOT need updating since it only checks a subset. Verify this after the change.

@docs/setup.md -- Existing setup documentation. The upgrade guide should cross-reference this for initial installation. The setup doc should NOT be modified (it already covers initial install).

@docs/troubleshooting.md -- Existing troubleshooting guide. The upgrade guide should link to this for common issues. The troubleshooting doc should NOT be modified.

@CLAUDE.md lines 182-209 -- Consumer and Contributor Skills tables. Add sm-upgrade row to the Consumer Skills table.
</context>
<tasks>
<task type="auto">
  <name>create-sm-upgrade-skill</name>
  <files>
    .claude/skills/sm-upgrade/SKILL.md
  </files>
  <action>
Create `.claude/skills/sm-upgrade/SKILL.md` following the established skill file pattern (frontmatter with name, description, allowed-tools, then markdown body).

Frontmatter:
```yaml
---
name: sm-upgrade
description: Use when upgrading SourceMonitor to a new gem version, including CHANGELOG review, running the upgrade command, interpreting verification results, and handling configuration deprecations.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---
```

Body sections (follow the pattern from sm-host-setup):

**# sm-upgrade: Gem Upgrade Workflow**

Brief intro: guides agents through upgrading SourceMonitor in a host Rails application after a new gem version is released.

**## When to Use**
- Host app is updating the source_monitor gem version in Gemfile
- User reports deprecation warnings after a gem update
- User wants to know what changed between versions
- Troubleshooting a broken upgrade
- Migrating configuration after breaking changes

**## Prerequisites**
Table: existing SourceMonitor installation (check `.source_monitor_version` or `config/initializers/source_monitor.rb`), access to CHANGELOG.md (bundled with gem).

**## Upgrade Workflow**

Step-by-step numbered workflow:
1. **Review CHANGELOG** -- Read `CHANGELOG.md` in the gem source. Identify changes between the current installed version (from `.source_monitor_version` or `Gemfile.lock`) and the target version. Focus on Added, Changed, Fixed, Removed sections. Flag any breaking changes or deprecation notices.
2. **Update Gemfile** -- Bump the version constraint in the host app's Gemfile: `gem "source_monitor", "~> X.Y"`. Run `bundle update source_monitor`.
3. **Run the upgrade command** -- `bin/source_monitor upgrade`. This automatically: detects the version change via `.source_monitor_version` marker, copies new migrations, re-runs the install generator (idempotent), runs the full verification suite.
4. **Run database migrations** -- `bin/rails db:migrate` if the upgrade command copied new migrations.
5. **Handle deprecation warnings** -- If the configure block in the initializer uses deprecated options, Rails logger will show warnings at boot. Read each warning, identify the replacement, update the initializer. See `sm-configure` skill for configuration reference.
6. **Run verification** -- `bin/source_monitor verify` to confirm all checks pass.
7. **Restart processes** -- Restart web server and Solid Queue workers to pick up the new version.

**## Interpreting Upgrade Results**

Table of verification check results and what they mean:
| Check | OK | Warning | Failure |
| PendingMigrations | All engine migrations present | - | Missing migrations need copying |
| SolidQueue | Workers running | - | Start Solid Queue workers |
| RecurringSchedule | Tasks registered | - | Re-run generator or check queue.yml |
| ActionCable | Adapter configured | - | Configure Solid Cable or Redis |

**## Handling Deprecation Warnings**

Explain the two severity levels:
- `:warning` -- Option renamed. The old name still works but logs a deprecation message. Update initializer to use the new option name. The message includes the replacement path.
- `:error` -- Option removed. Using the old name raises `SourceMonitor::DeprecatedOptionError`. You must remove or replace the option before the app can boot.

Pattern for fixing:
1. Read the deprecation message (logged to Rails.logger or raised as error)
2. Find the replacement option path in the message
3. Update `config/initializers/source_monitor.rb`
4. Restart and verify

**## Edge Cases**

- **First install (no .source_monitor_version file):** Upgrade command treats this as a version change and runs the full workflow. Safe to run on first install.
- **Same version (no change):** Command reports "Already up to date (vX.Y.Z)" and exits cleanly.
- **Skipped versions (e.g., 0.2.0 to 0.4.0):** Read all CHANGELOG sections between the two versions. Multiple migrations may need running.
- **Failed verification after upgrade:** Read the verification output. Most common: pending migrations (run db:migrate), missing Solid Queue workers (start workers), stale recurring schedule (re-run generator).
- **Custom scrapers or event handlers:** Check CHANGELOG for API changes in Scrapers::Base or event callback signatures.

**## Key Source Files**

Table mapping file to purpose:
| File | Purpose |
| `lib/source_monitor/setup/upgrade_command.rb` | Upgrade orchestrator |
| `lib/source_monitor/setup/cli.rb` | CLI entry point (`bin/source_monitor upgrade`) |
| `lib/source_monitor/setup/verification/runner.rb` | Verification runner (4 verifiers) |
| `lib/source_monitor/configuration/deprecation_registry.rb` | Deprecation framework |
| `CHANGELOG.md` | Version history (Keep a Changelog format) |
| `.source_monitor_version` | Version marker in host app root |

**## References**
- `docs/upgrade.md` -- Human-readable upgrade guide
- `docs/setup.md` -- Initial setup documentation
- `docs/troubleshooting.md` -- Common issues and fixes
- `sm-host-setup` skill -- Initial installation workflow
- `sm-configure` skill -- Configuration reference for updating deprecated options

**## Checklist**
- [ ] CHANGELOG reviewed for version range
- [ ] Gemfile updated and `bundle update source_monitor` run
- [ ] `bin/source_monitor upgrade` completed successfully
- [ ] Database migrations applied if needed
- [ ] Deprecation warnings addressed in initializer
- [ ] `bin/source_monitor verify` passes all checks
- [ ] Web server and workers restarted
  </action>
  <verify>
Read the created file. Confirm: (a) frontmatter has name/description/allowed-tools, (b) all 8 body sections present (When to Use, Prerequisites, Upgrade Workflow, Interpreting Results, Handling Deprecation Warnings, Edge Cases, Key Source Files, References), (c) references upgrade_command.rb, cli.rb, verification runner, deprecation_registry.rb, (d) covers CHANGELOG parsing workflow, (e) documents both :warning and :error deprecation severities, (f) checklist present.
  </verify>
  <done>
sm-upgrade SKILL.md created with comprehensive upgrade workflow guide covering CHANGELOG parsing, upgrade command, verification interpretation, deprecation handling, and edge cases.
  </done>
</task>
<task type="auto">
  <name>create-sm-upgrade-reference-files</name>
  <files>
    .claude/skills/sm-upgrade/reference/upgrade-workflow.md
    .claude/skills/sm-upgrade/reference/version-history.md
  </files>
  <action>
Create two reference files in `.claude/skills/sm-upgrade/reference/`.

**File 1: `upgrade-workflow.md`**

Detailed step-by-step reference that agents can follow mechanically. This is more prescriptive than the SKILL.md overview.

Title: "Upgrade Workflow Reference"

Sections:

**## Pre-Upgrade Checklist**
1. Identify current version: `grep source_monitor Gemfile.lock` or `cat .source_monitor_version`
2. Identify target version: check RubyGems or GitHub releases
3. Read CHANGELOG.md between those versions (in gem source: `bundle show source_monitor` to find gem path, then read CHANGELOG.md)
4. Note any breaking changes, removed options, or new required configuration

**## CHANGELOG Parsing Guide**
- Format: Keep a Changelog (https://keepachangelog.com)
- Each version has a `## [X.Y.Z] - YYYY-MM-DD` header
- Subsections: Added, Changed, Fixed, Removed, Deprecated, Security
- For multi-version jumps, read ALL sections between current and target
- Key things to flag: "Removed" entries (breaking), "Changed" entries (behavioral), "Deprecated" entries (action needed)
- Example: To upgrade from 0.3.1 to 0.4.0, read sections [0.3.2], [0.3.3], and [0.4.0]

**## Upgrade Command Internals**
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

**## Post-Upgrade Verification**
Detailed explanation of each verifier:
- **PendingMigrationsVerifier**: Checks that all SourceMonitor migrations in the gem have corresponding files in host `db/migrate/`. Warns if any are missing or not yet run. Fix: `bin/rails db:migrate`.
- **SolidQueueVerifier**: Checks that Solid Queue workers are running. Fix: start workers via `bin/rails solid_queue:start` or ensure `Procfile.dev` has a `jobs:` entry.
- **RecurringScheduleVerifier**: Checks that SourceMonitor recurring tasks (ScheduleFetchesJob, scrape scheduling, cleanup jobs) are registered in Solid Queue. Fix: ensure `config/recurring.yml` exists and `config/queue.yml` dispatchers have `recurring_schedule: config/recurring.yml`.
- **ActionCableVerifier**: Checks that Action Cable is configured with a production-ready adapter (Solid Cable or Redis). Fix: add Solid Cable gem or configure Redis adapter.

**## Troubleshooting Common Upgrade Issues**
- "Already up to date" but expected changes: Check that `bundle update source_monitor` actually pulled the new version. Verify `Gemfile.lock` shows the expected version.
- Migrations fail: Check for conflicting migration timestamps. Remove duplicates and re-run `bin/rails db:migrate`.
- Deprecation errors at boot: Option was removed. Check the error message for the replacement. Update initializer before restarting.
- Generator fails: Usually safe to re-run manually: `bin/rails generate source_monitor:install`. It is idempotent.

**File 2: `version-history.md`**

Version-specific upgrade notes for each major/minor version transition.

Title: "Version-Specific Upgrade Notes"

**## 0.3.x to 0.4.0**
Released: 2026-02-12

Key changes:
- Install generator now auto-patches `Procfile.dev` and `queue.yml` dispatcher config
- New Active Storage image download feature (opt-in via `config.images.download_to_active_storage`)
- SSL certificate store configuration added to HTTPSettings
- RecurringScheduleVerifier and SolidQueueVerifier enhanced with better remediation messages

Action items:
1. Re-run `bin/source_monitor upgrade` (or `bin/rails generate source_monitor:install`) to get Procfile.dev and queue.yml patches
2. If using Active Storage image downloads, add `config.images.download_to_active_storage = true` to initializer
3. If experiencing SSL certificate errors, new `config.http.ssl_*` settings are available
4. No breaking changes -- all existing configuration remains valid

**## 0.2.x to 0.3.0**
Released: 2026-02-10

Key changes:
- Major refactoring: FeedFetcher, Configuration, ImportSessionsController, ItemCreator all extracted into smaller modules
- Ruby autoload replaces eager requires in `lib/source_monitor.rb`
- LogEntry no longer uses hard-coded table name
- Skills system added (14 `sm-*` skills)

Action items:
1. If you monkey-patched or referenced internal classes (FeedFetcher internals, Configuration nested classes), check that your references still resolve
2. Run `bin/source_monitor upgrade` to copy any new migrations
3. Optionally install skills: `bin/rails source_monitor:skills:install`
4. No configuration changes required -- public API unchanged

**## 0.1.x to 0.2.0**
Released: 2025-11-25

Key changes:
- OPML import wizard added
- ImportHistory model and migrations added

Action items:
1. Copy and run new migrations: `bin/rails railties:install:migrations FROM=source_monitor && bin/rails db:migrate`
2. No configuration changes required

**## Future Versions**
Template for documenting future upgrades:
```
## X.Y.Z to A.B.C
Released: YYYY-MM-DD

Key changes:
- ...

Action items:
1. ...

Deprecations:
- `old_option` replaced by `new_option` (warning in A.B.C, removal planned for D.E.F)
```
  </action>
  <verify>
Read both created files. Confirm: (a) upgrade-workflow.md has Pre-Upgrade Checklist, CHANGELOG Parsing Guide, Upgrade Command Internals, Post-Upgrade Verification, and Troubleshooting sections, (b) version-history.md has sections for 0.3.x->0.4.0, 0.2.x->0.3.0, 0.1.x->0.2.0 transitions, (c) both files reference correct file paths and command names, (d) upgrade-workflow.md documents all 4 verifiers.
  </verify>
  <done>
Two reference files created: upgrade-workflow.md with detailed mechanical workflow and CHANGELOG parsing guide; version-history.md with version-specific migration notes for all released transitions.
  </done>
</task>
<task type="auto">
  <name>create-docs-upgrade-and-cross-reference-host-setup</name>
  <files>
    docs/upgrade.md
    .claude/skills/sm-host-setup/SKILL.md
  </files>
  <action>
**File 1: Create `docs/upgrade.md`**

Human-readable upgrade guide (REQ-30). This is for developers reading docs, not AI agents.

Title: "# SourceMonitor Upgrade Guide"

**## General Upgrade Steps**

Numbered list:
1. Review the [CHANGELOG](../CHANGELOG.md) for changes between your current and target versions
2. Update your Gemfile version constraint and run `bundle update source_monitor`
3. Run the upgrade command: `bin/source_monitor upgrade`
4. Apply database migrations if new ones were copied: `bin/rails db:migrate`
5. Address any deprecation warnings in your initializer (see Deprecation Handling below)
6. Run verification: `bin/source_monitor verify`
7. Restart your web server and background workers

**## Quick Upgrade (Most Cases)**

```bash
# 1. Update the gem
bundle update source_monitor

# 2. Run the upgrade command (handles migrations, generator, verification)
bin/source_monitor upgrade

# 3. Migrate if needed
bin/rails db:migrate

# 4. Restart
# (restart web server and Solid Queue workers)
```

**## Deprecation Handling**

When upgrading, you may see deprecation warnings in your Rails log:

```
[SourceMonitor] DEPRECATION: 'http.old_option' was deprecated in v0.5.0 and replaced by 'http.new_option'.
```

To resolve:
1. Open `config/initializers/source_monitor.rb`
2. Find the deprecated option (e.g., `config.http.old_option = value`)
3. Replace with the new option from the warning message (e.g., `config.http.new_option = value`)
4. Restart and verify the warning is gone

If a removed option raises an error (`SourceMonitor::DeprecatedOptionError`), you must update the initializer before the app can boot.

**## Version-Specific Notes**

### Upgrading to 0.4.0 (from 0.3.x)

**Released:** 2026-02-12

**What changed:**
- Install generator now auto-patches `Procfile.dev` with a Solid Queue `jobs:` entry
- Install generator now patches `config/queue.yml` dispatcher with `recurring_schedule: config/recurring.yml`
- Active Storage image download feature added (opt-in)
- SSL certificate configuration added to HTTP settings
- Enhanced verification messages for SolidQueue and RecurringSchedule verifiers

**Upgrade steps:**
```bash
bundle update source_monitor
bin/source_monitor upgrade
bin/rails db:migrate
```

**Notes:**
- No breaking changes. All existing configuration remains valid.
- Re-running the generator (`bin/rails generate source_monitor:install`) will add missing `Procfile.dev` and `queue.yml` entries without overwriting existing config.
- New optional features: `config.images.download_to_active_storage = true`, `config.http.ssl_ca_file`, `config.http.ssl_ca_path`, `config.http.ssl_verify`.

### Upgrading to 0.3.0 (from 0.2.x)

**Released:** 2026-02-10

**What changed:**
- Internal refactoring: FeedFetcher, Configuration, ImportSessionsController, and ItemCreator extracted into smaller modules
- Eager requires replaced with Ruby autoload
- Skills system added (14 `sm-*` Claude Code skills)

**Upgrade steps:**
```bash
bundle update source_monitor
bin/source_monitor upgrade
bin/rails db:migrate
```

**Notes:**
- No breaking changes to the public API.
- If you referenced internal classes directly (e.g., `SourceMonitor::FeedFetcher` internals), verify your code against the new module structure.
- Optionally install AI skills: `bin/rails source_monitor:skills:install`

### Upgrading to 0.2.0 (from 0.1.x)

**Released:** 2025-11-25

**What changed:**
- OPML import wizard with multi-step flow
- New `ImportHistory` model and associated migrations

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails railties:install:migrations FROM=source_monitor
bin/rails db:migrate
```

**Notes:**
- New database tables required. Run migrations after updating.
- No configuration changes needed.

**## Troubleshooting**

### "Already up to date" but I expected changes
- Verify the gem version actually changed: `bundle show source_monitor`
- Check `Gemfile.lock` for the resolved version
- If the `.source_monitor_version` marker was manually edited, delete it and re-run upgrade

### Migrations fail with duplicate timestamps
- Remove the duplicate migration file from `db/migrate/` (keep the newer one)
- Re-run `bin/rails db:migrate`

### Deprecation error prevents boot
- Read the error message for the replacement option
- Update your initializer before restarting
- If unsure which option to use, consult `docs/configuration.md`

### Verification failures after upgrade
- **PendingMigrations:** Run `bin/rails db:migrate`
- **SolidQueue:** Ensure workers are running. Check `Procfile.dev` for a `jobs:` entry.
- **RecurringSchedule:** Re-run `bin/rails generate source_monitor:install` to patch `config/queue.yml`
- **ActionCable:** Configure Solid Cable or Redis adapter

For additional help, see [Troubleshooting](troubleshooting.md).

**## See Also**
- [Setup Guide](setup.md) -- Initial installation
- [Configuration Reference](configuration.md) -- All configuration options
- [Troubleshooting](troubleshooting.md) -- Common issues and fixes
- [CHANGELOG](../CHANGELOG.md) -- Full version history

---

**File 2: Update `.claude/skills/sm-host-setup/SKILL.md`**

Make two changes:

1. In the "## When to Use" section, change the bullet "Re-running setup after upgrading the gem" to:
   "Re-running setup after upgrading the gem (see also: `sm-upgrade` skill for full upgrade workflow)"

2. In the "## References" section at the bottom, add a new bullet:
   "- `sm-upgrade` skill -- Upgrade workflow for gem version updates"

3. In the "## Testing" section, after item 3 ("Create a source and trigger..."), add item 4:
   "4. For subsequent gem updates, use `bin/source_monitor upgrade` -- see the `sm-upgrade` skill"
  </action>
  <verify>
Read `docs/upgrade.md`. Confirm: (a) General Upgrade Steps section with 7 steps, (b) Quick Upgrade section with bash commands, (c) Deprecation Handling section with example warning message, (d) version-specific notes for 0.4.0, 0.3.0, 0.2.0, (e) Troubleshooting section with 4 subsections, (f) See Also section linking to setup, configuration, troubleshooting, CHANGELOG.

Read `.claude/skills/sm-host-setup/SKILL.md`. Confirm: (a) "When to Use" bullet updated to reference sm-upgrade, (b) References section includes sm-upgrade, (c) Testing section includes item 4 referencing sm-upgrade.
  </verify>
  <done>
docs/upgrade.md created with general steps, quick upgrade commands, deprecation handling, version-specific notes for all 3 major transitions, and troubleshooting. sm-host-setup SKILL.md updated with 3 cross-references to sm-upgrade.
  </done>
</task>
<task type="auto">
  <name>update-skills-installer-and-catalog</name>
  <files>
    lib/source_monitor/setup/skills_installer.rb
    test/lib/source_monitor/setup/skills_installer_test.rb
    CLAUDE.md
  </files>
  <action>
**File 1: Update `lib/source_monitor/setup/skills_installer.rb`**

Add `sm-upgrade` to the CONSUMER_SKILLS constant. Insert it in alphabetical order within the array:

```ruby
CONSUMER_SKILLS = %w[
  sm-configure sm-dashboard-widget sm-event-handler
  sm-host-setup sm-model-extension sm-scraper-adapter
  sm-upgrade
].freeze
```

Note: the original order is not strictly alphabetical (sm-host-setup comes first). Maintain the existing grouping style but add sm-upgrade at the end of the array (after sm-dashboard-widget, before the closing bracket), keeping the same line-break pattern:

```ruby
CONSUMER_SKILLS = %w[
  sm-host-setup sm-configure sm-scraper-adapter
  sm-event-handler sm-model-extension sm-dashboard-widget
  sm-upgrade
].freeze
```

**File 2: Update `test/lib/source_monitor/setup/skills_installer_test.rb`**

The existing tests iterate `SkillsInstaller::CONSUMER_SKILLS` dynamically, so they will automatically pick up the new entry. However, the first test "install defaults to consumer group" only creates 3 fake skills ("sm-dashboard-widget", "sm-host-setup", "sm-domain-model"). It checks that consumer skills are installed and contributor skills are not. Since sm-upgrade is now in CONSUMER_SKILLS, the test might need adjustment if it checks the result count.

Review the test: it creates sm-dashboard-widget and sm-host-setup as consumer fakes, then asserts they are in `result[:installed]` and sm-domain-model is NOT. Since sm-upgrade is not created as a fake skill in this test, it simply will not appear in installed or skipped -- the installer only processes skills that exist on disk. So the test should still pass as-is.

However, add a NEW test to explicitly verify sm-upgrade is included in the consumer group:

```ruby
test "sm-upgrade is included in consumer skills" do
  assert_includes SkillsInstaller::CONSUMER_SKILLS, "sm-upgrade"
end
```

This is a simple, fast assertion that documents the requirement.

**File 3: Update `CLAUDE.md`**

In the Consumer Skills table (around line 188-195), add a new row after the sm-dashboard-widget row:

```markdown
| `sm-upgrade` | Gem upgrade workflow with CHANGELOG parsing |
```

The updated table should read:
```markdown
| Skill | Purpose |
|-------|---------|
| `sm-host-setup` | Full host app setup walkthrough |
| `sm-configure` | DSL configuration across all sub-sections |
| `sm-scraper-adapter` | Custom scraper inheriting `Scrapers::Base` |
| `sm-event-handler` | Lifecycle callbacks (after_item_created, etc.) |
| `sm-model-extension` | Extend engine models from host app |
| `sm-dashboard-widget` | Dashboard queries, presenters, Turbo broadcasts |
| `sm-upgrade` | Gem upgrade workflow with CHANGELOG parsing |
```
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/skills_installer_test.rb` -- all tests pass (11 existing + 1 new = 12 tests). Run `bin/rubocop lib/source_monitor/setup/skills_installer.rb` -- 0 offenses. Confirm `grep 'sm-upgrade' lib/source_monitor/setup/skills_installer.rb` returns a match. Confirm `grep 'sm-upgrade' CLAUDE.md` returns a match. Confirm `grep 'sm-upgrade' test/lib/source_monitor/setup/skills_installer_test.rb` returns a match.
  </verify>
  <done>
Skills installer updated with sm-upgrade in CONSUMER_SKILLS. New test asserts sm-upgrade inclusion. CLAUDE.md consumer skills table updated with sm-upgrade row.
  </done>
</task>
<task type="auto">
  <name>full-suite-verification</name>
  <files>
  </files>
  <action>
Run the full verification suite to confirm no regressions and all quality gates pass.

1. `bin/rails test` -- full test suite passes with 1002+ runs, 0 failures
2. `bin/rubocop` -- 0 offenses across all files
3. `bin/brakeman --no-pager` -- 0 warnings

If any failures:
- Test failures: read the failure output, identify the root cause, fix in the appropriate file
- RuboCop offenses: fix style issues in the offending files
- Brakeman warnings: evaluate and fix security concerns

After all gates pass, confirm all Phase 3 artifacts exist:
- `ls -la .claude/skills/sm-upgrade/SKILL.md` -- file exists
- `ls -la .claude/skills/sm-upgrade/reference/upgrade-workflow.md` -- file exists
- `ls -la .claude/skills/sm-upgrade/reference/version-history.md` -- file exists
- `ls -la docs/upgrade.md` -- file exists
- `grep 'sm-upgrade' lib/source_monitor/setup/skills_installer.rb` -- match found
- `grep 'sm-upgrade' CLAUDE.md` -- match found
- `grep 'sm-upgrade' .claude/skills/sm-host-setup/SKILL.md` -- match found (cross-reference)
- `grep 'sm-upgrade' test/lib/source_monitor/setup/skills_installer_test.rb` -- match found

All success criteria met:
- REQ-29: sm-upgrade skill covers CHANGELOG parsing, upgrade command, verification results, deprecation handling, edge cases
- REQ-30: docs/upgrade.md includes general steps, version-specific notes (0.1.x through 0.4.0), troubleshooting
- Skills installer includes sm-upgrade in consumer set
- sm-host-setup cross-references upgrade flow
  </action>
  <verify>
`bin/rails test` exits 0 with 1002+ runs, 0 failures. `bin/rubocop` exits 0. `bin/brakeman --no-pager` exits 0. All 8 grep/ls checks return matches.
  </verify>
  <done>
Full suite green with 1002+ runs. RuboCop clean. Brakeman clean. All Phase 3 success criteria met. REQ-29 and REQ-30 implemented: sm-upgrade skill with comprehensive upgrade workflow, docs/upgrade.md with versioned instructions, skills installer updated, sm-host-setup cross-referenced.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/setup/skills_installer_test.rb` -- 12 tests pass
2. `bin/rails test` -- 1002+ runs, 0 failures
3. `bin/rubocop` -- 0 offenses
4. `bin/brakeman --no-pager` -- 0 warnings
5. `ls .claude/skills/sm-upgrade/SKILL.md` -- file exists
6. `ls .claude/skills/sm-upgrade/reference/upgrade-workflow.md` -- file exists
7. `ls .claude/skills/sm-upgrade/reference/version-history.md` -- file exists
8. `ls docs/upgrade.md` -- file exists
9. `grep -n 'sm-upgrade' lib/source_monitor/setup/skills_installer.rb` -- match in CONSUMER_SKILLS
10. `grep -n 'sm-upgrade' CLAUDE.md` -- match in Consumer Skills table
11. `grep -n 'sm-upgrade' .claude/skills/sm-host-setup/SKILL.md` -- match in cross-references
12. `grep -n 'sm-upgrade' test/lib/source_monitor/setup/skills_installer_test.rb` -- match in test assertion
</verification>
<success_criteria>
- sm-upgrade skill covers: reading CHANGELOG between versions, running upgrade command, interpreting results, handling edge cases (REQ-29)
- Skill references the upgrade command (upgrade_command.rb) and verification suite (runner.rb) (REQ-29)
- docs/upgrade.md includes: general upgrade steps, version-specific notes (0.1.x through 0.4.0), troubleshooting (REQ-30)
- Skills installer updated to include sm-upgrade in consumer set
- Existing sm-host-setup skill cross-references upgrade flow
- CLAUDE.md updated with sm-upgrade in Consumer Skills table
- bin/rails test passes with 1002+ runs, RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/03-upgrade-skill-docs/PLAN-01-SUMMARY.md
</output>
