---
phase: 3
plan: "01"
title: skills-docs-alignment
type: execute
wave: 1
depends_on: []
cross_phase_deps:
  - phase: 1
    artifact: "lib/generators/source_monitor/install/install_generator.rb"
    reason: "Phase 1 added patch_procfile_dev and configure_queue_dispatcher -- docs must reflect these"
  - phase: 2
    artifact: "lib/source_monitor/setup/verification/recurring_schedule_verifier.rb"
    reason: "Phase 2 added RecurringScheduleVerifier -- troubleshooting and verification docs must reference it"
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - .claude/skills/sm-host-setup/SKILL.md
  - .claude/skills/sm-host-setup/reference/setup-checklist.md
  - .claude/skills/sm-configure/SKILL.md
  - .claude/skills/sm-job/SKILL.md
  - docs/setup.md
  - docs/troubleshooting.md
must_haves:
  truths:
    - "grep 'Procfile.dev' .claude/skills/sm-host-setup/SKILL.md returns matches that describe automatic patching, not manual steps"
    - "grep 'recurring_schedule' .claude/skills/sm-host-setup/SKILL.md returns matches that describe automatic wiring, not manual configuration"
    - "grep 'automatically' .claude/skills/sm-host-setup/reference/setup-checklist.md returns matches in the Phase 6 worker config section"
    - "grep 'recurring_schedule' .claude/skills/sm-configure/SKILL.md returns matches referencing automatic dispatcher wiring"
    - "grep 'automatically' docs/setup.md returns matches describing generator automation of Procfile.dev and queue.yml"
    - "grep 'RecurringScheduleVerifier\\|recurring schedule' docs/troubleshooting.md returns matches in the recurring jobs and diagnostics sections"
    - "The sm-host-setup SKILL.md 'What the Install Generator Does' section lists 5 actions (not 3)"
    - "The sm-host-setup SKILL.md checklist shows Procfile.dev and dispatcher items as auto-handled (not manual checkboxes)"
    - "The setup-checklist.md Phase 6a and 6b sections note that the generator handles these automatically"
    - "The docs/setup.md manual installation steps 6a and 6b note that the generator handles these automatically"
    - "The docs/troubleshooting.md Issue #4 and #5 mention running the generator as the primary fix"
  artifacts:
    - path: ".claude/skills/sm-host-setup/SKILL.md"
      provides: "Updated skill reflecting 5-action generator with auto Procfile.dev and queue.yml patching"
      contains: "Patches Procfile.dev"
    - path: ".claude/skills/sm-host-setup/reference/setup-checklist.md"
      provides: "Updated checklist with automated Phase 6a/6b"
      contains: "generator handles this automatically"
    - path: ".claude/skills/sm-configure/SKILL.md"
      provides: "Updated configure skill referencing automatic dispatcher wiring"
      contains: "recurring_schedule"
    - path: "docs/setup.md"
      provides: "Updated setup docs noting generator automation"
      contains: "generator automatically"
    - path: "docs/troubleshooting.md"
      provides: "Updated troubleshooting with generator-first remediation and RecurringScheduleVerifier reference"
      contains: "RecurringScheduleVerifier"
  key_links:
    - from: ".claude/skills/sm-host-setup/SKILL.md"
      to: "REQ-21"
      via: "sm-host-setup skill reflects new generator capabilities"
    - from: ".claude/skills/sm-configure/SKILL.md"
      to: "REQ-21"
      via: "sm-configure skill references automatic recurring_schedule wiring"
    - from: "docs/setup.md"
      to: "REQ-21"
      via: "Setup docs updated to note generator handles both automatically"
    - from: "docs/troubleshooting.md"
      to: "REQ-21"
      via: "Troubleshooting updated with improved diagnostics"
    - from: ".claude/skills/sm-host-setup/reference/setup-checklist.md"
      to: "REQ-21"
      via: "Setup checklist reflects automation"
---
<objective>
Update all sm-* skills and documentation files to reflect that the install generator now automatically handles Procfile.dev patching and queue.yml dispatcher wiring (added in Phase 1). Remove manual instructions that are now automated. Update troubleshooting to reference the RecurringScheduleVerifier (added in Phase 2). REQ-21.
</objective>
<context>
@lib/generators/source_monitor/install/install_generator.rb -- The generator now has 5 public methods executed in order: (1) add_routes_mount, (2) create_initializer, (3) configure_recurring_jobs, (4) patch_procfile_dev, (5) configure_queue_dispatcher, plus print_next_steps. The docs currently describe only 3 actions. The Procfile.dev step creates the file with web: + jobs: entries if missing, appends jobs: if present without it, or skips if already there. The queue.yml step adds recurring_schedule to dispatchers or creates a default dispatcher section.

@lib/source_monitor/setup/workflow.rb -- The guided workflow now calls procfile_patcher.patch and queue_config_patcher.patch after the install generator runs and before verification. Both patchers are unconditional (no user prompt).

@lib/source_monitor/setup/verification/recurring_schedule_verifier.rb -- New verifier (Phase 2) that checks SolidQueue recurring tasks are registered. Warns when no SM tasks found, errors when SolidQueue unavailable. Wired into Runner.default_verifiers.

@lib/source_monitor/setup/verification/solid_queue_verifier.rb -- Remediation now mentions Procfile.dev (Phase 2 change).

@.claude/skills/sm-host-setup/SKILL.md -- Lines 76-80 still have manual Procfile/queue comments in the Manual Step-by-Step section. Lines 93-109 describe only 3 generator actions. Lines 230-231 have manual checklist items.

@.claude/skills/sm-host-setup/reference/setup-checklist.md -- Phase 6a (lines 103-115) and Phase 6b (lines 115-127) describe manual Procfile.dev and recurring schedule wiring.

@.claude/skills/sm-configure/SKILL.md -- Line 149 has queue names checklist item. Needs a note about automatic recurring_schedule wiring.

@.claude/skills/sm-job/SKILL.md -- Lines 162-171 describe recurring jobs. Could mention that the generator also wires the dispatcher automatically.

@docs/setup.md -- Lines 54-67 have manual Procfile.dev and queue.yml guidance that should note the generator handles these.

@docs/troubleshooting.md -- Issues #4 (lines 23-34) and #5 (lines 36-44) should recommend re-running the generator as the primary fix and mention bin/source_monitor verify for diagnostics.

**Rationale:** Phase 1 automated Procfile.dev and queue.yml patching. Phase 2 added RecurringScheduleVerifier for diagnostics. All docs and skills still describe the pre-Phase-1 manual workflow. This plan updates every consumer-facing document to reflect the current automated behavior, eliminating confusion for new users.
</context>
<tasks>
<task type="auto">
  <name>update-sm-host-setup-skill</name>
  <files>
    .claude/skills/sm-host-setup/SKILL.md
  </files>
  <action>
Update the sm-host-setup SKILL.md in three areas:

**1. Manual Step-by-Step section (lines 73-84):**

Replace the manual comments on lines 76-80:
```
# 5a. If your host uses bin/dev (foreman/overmind), add a jobs: entry to Procfile.dev:
#     jobs: bundle exec rake solid_queue:start

# 5b. Ensure your dispatcher config in config/queue.yml includes
#     recurring_schedule: config/recurring.yml so recurring jobs are loaded.
```

With a note that these are now handled automatically:
```
# Note: The generator automatically patches Procfile.dev with a jobs: entry
# and adds recurring_schedule to your queue.yml dispatcher config.
# Re-run the generator if these were not applied: bin/rails generate source_monitor:install
```

**2. "What the Install Generator Does" section (lines 93-109):**

Update from "performs three actions" to "performs five actions" and add items 4 and 5:

4. **Patches Procfile.dev** with a `jobs:` entry for Solid Queue:
   Creates the file with `web:` and `jobs:` entries if it does not exist. Appends a `jobs:` entry if the file exists but lacks one. Skips if a `jobs:` entry is already present.

5. **Patches queue.yml dispatcher** with `recurring_schedule: config/recurring.yml`:
   Adds the `recurring_schedule` key to each dispatcher entry in `config/queue.yml`. If no dispatchers section exists, creates a default one. Skips if `recurring_schedule` is already configured. Skips if `config/queue.yml` does not exist.

**3. Checklist section (lines 222-236):**

Change lines 230-231 from manual checkboxes:
```
- [ ] `Procfile.dev` includes `jobs:` entry for Solid Queue (for `bin/dev` usage)
- [ ] Dispatcher config includes `recurring_schedule: config/recurring.yml`
```

To auto-handled items:
```
- [x] `Procfile.dev` includes `jobs:` entry for Solid Queue (handled by generator)
- [x] Dispatcher config includes `recurring_schedule: config/recurring.yml` (handled by generator)
```

Also update the Key Source Files table to add the two new setup helpers:
```
| `lib/source_monitor/setup/procfile_patcher.rb` | Procfile.dev patching for guided workflow |
| `lib/source_monitor/setup/queue_config_patcher.rb` | Queue config patching for guided workflow |
```
  </action>
  <verify>
Read the modified file. Confirm: (a) manual comments on lines 76-80 are replaced with automation note, (b) "What the Install Generator Does" lists 5 actions, (c) checklist items for Procfile.dev and dispatcher are marked [x] with "(handled by generator)", (d) Key Source Files table includes the two new patcher files.
  </verify>
  <done>
sm-host-setup SKILL.md updated to reflect 5-action generator with automatic Procfile.dev and queue.yml handling. Manual steps replaced with automation notes. Checklist items marked as auto-handled.
  </done>
</task>
<task type="auto">
  <name>update-setup-checklist</name>
  <files>
    .claude/skills/sm-host-setup/reference/setup-checklist.md
  </files>
  <action>
Update the setup-checklist.md to reflect that Phase 6a and 6b are now automated by the generator.

**Phase 6a (lines 103-114):**

Replace the manual instruction block:
```
### Phase 6a: Wire Procfile.dev for Development

Most Rails 8 apps use `bin/dev` (via foreman or overmind) to start all processes. The host app's `Procfile.dev` must include a `jobs:` entry so Solid Queue workers start alongside the web server:

```
# Procfile.dev
web: bin/rails server -p 3000
jobs: bundle exec rake solid_queue:start
```

Without this line, `bin/dev` will start the web server but jobs will never process.
```

With:
```
### Phase 6a: Procfile.dev for Development (Automatic)

The install generator automatically patches `Procfile.dev` with a `jobs:` entry for Solid Queue. If no `Procfile.dev` exists, it creates one with `web:` and `jobs:` entries. If the file exists but lacks a `jobs:` entry, it appends one. This is idempotent -- re-running the generator is safe.

Verify after running the generator:
```
# Expected Procfile.dev content:
web: bin/rails server -p 3000
jobs: bundle exec rake solid_queue:start
```

If the entry is missing, re-run: `bin/rails generate source_monitor:install`
```

**Phase 6b (lines 115-127):**

Replace the manual instruction block:
```
### Phase 6b: Wire Recurring Schedule into Dispatcher

The install generator creates `config/recurring.yml` with SourceMonitor's recurring jobs, but the dispatcher must explicitly reference this file. In `config/queue.yml` (or `config/solid_queue.yml`), add `recurring_schedule` to the dispatchers section:

```yaml
dispatchers:
  - polling_interval: 1
    batch_size: 500
    recurring_schedule: config/recurring.yml
```

Without this key, Solid Queue's dispatcher will not load recurring jobs even though the file exists. Sources will never auto-fetch and cleanup jobs will never fire.
```

With:
```
### Phase 6b: Recurring Schedule Dispatcher Wiring (Automatic)

The install generator automatically patches `config/queue.yml` dispatchers with `recurring_schedule: config/recurring.yml`. If no dispatchers section exists, it creates a default one. This is idempotent -- re-running the generator is safe.

Verify after running the generator:
```yaml
# Expected in config/queue.yml under dispatchers:
dispatchers:
  - polling_interval: 1
    batch_size: 500
    recurring_schedule: config/recurring.yml
```

If the key is missing, re-run: `bin/rails generate source_monitor:install`

**Diagnostics:** Run `bin/source_monitor verify` to check that recurring tasks are registered. The RecurringScheduleVerifier will warn if no SourceMonitor recurring tasks are found in Solid Queue.
```

**Checklist items (lines 128-131):**

Update the checklist items to reflect automation:
```
- [x] `Procfile.dev` includes a `jobs:` entry for Solid Queue (handled by generator)
- [x] Dispatcher config includes `recurring_schedule: config/recurring.yml` (handled by generator)
```
  </action>
  <verify>
Read the modified file. Confirm: (a) Phase 6a title includes "(Automatic)", (b) Phase 6b title includes "(Automatic)", (c) both sections describe generator behavior not manual steps, (d) both include "re-run" guidance, (e) Phase 6b mentions RecurringScheduleVerifier, (f) checklist items marked [x] with "(handled by generator)".
  </verify>
  <done>
setup-checklist.md updated with automated Phase 6a/6b sections. Manual steps replaced with generator behavior descriptions and verification guidance.
  </done>
</task>
<task type="auto">
  <name>update-sm-configure-and-sm-job-skills</name>
  <files>
    .claude/skills/sm-configure/SKILL.md
    .claude/skills/sm-job/SKILL.md
  </files>
  <action>
**sm-configure SKILL.md:**

In the Checklist section (line 149), update:
```
- [ ] Queue names match `config/solid_queue.yml` entries
```

To:
```
- [ ] Queue names match `config/queue.yml` (or `config/solid_queue.yml`) entries
- [x] Dispatcher config includes `recurring_schedule: config/recurring.yml` (handled by install generator)
```

This adds a new checklist item noting the automatic dispatcher wiring.

**sm-job SKILL.md:**

In the Recurring Jobs section (lines 162-171), update the text after the table:
```
These run automatically with `bin/dev` or `bin/jobs`. If you need to customize, edit `config/recurring.yml` directly.
```

To:
```
The install generator automatically configures `config/recurring.yml` with these entries AND patches the `config/queue.yml` dispatcher with `recurring_schedule: config/recurring.yml` so recurring jobs load on startup. Both steps are idempotent. If you need to customize schedules, edit `config/recurring.yml` directly.
```
  </action>
  <verify>
Read both modified files. Confirm: (a) sm-configure checklist has new dispatcher item marked [x], (b) sm-job recurring jobs section mentions automatic queue.yml patching.
  </verify>
  <done>
sm-configure and sm-job skills updated to reference automatic dispatcher wiring by the install generator.
  </done>
</task>
<task type="auto">
  <name>update-setup-docs</name>
  <files>
    docs/setup.md
  </files>
  <action>
Update docs/setup.md to reflect generator automation in two areas:

**1. Guided Setup section (lines 48-67):**

Replace the manual Procfile.dev and queue.yml guidance:
```
3. **Start background workers:**
   ```bash
   bin/rails solid_queue:start
   ```
   Recurring jobs (fetch scheduling, scraping, cleanup) are automatically configured in `config/recurring.yml` by the install generator. They'll run automatically with `bin/dev` or `bin/jobs`.

   **For development with `bin/dev`:** Ensure `Procfile.dev` includes a `jobs:` entry so Solid Queue workers start alongside the web server:
   ```
   jobs: bundle exec rake solid_queue:start
   ```

   **For recurring jobs:** Ensure the dispatcher in `config/queue.yml` (or `config/solid_queue.yml`) references the recurring schedule:
   ```yaml
   dispatchers:
     - polling_interval: 1
       batch_size: 500
       recurring_schedule: config/recurring.yml
   ```
   Without this key, Solid Queue will not load recurring jobs even though the file exists.
```

With:
```
3. **Start background workers:**
   ```bash
   bin/rails solid_queue:start
   ```
   The install generator automatically handles all worker configuration:
   - **Recurring jobs** are configured in `config/recurring.yml` (fetch scheduling, scraping, cleanup).
   - **Procfile.dev** is patched with a `jobs:` entry so `bin/dev` starts Solid Queue alongside the web server.
   - **Queue dispatcher** is patched with `recurring_schedule: config/recurring.yml` in `config/queue.yml` so recurring jobs load on startup.

   All three steps are idempotent. If any configuration is missing, re-run: `bin/rails generate source_monitor:install`
```

**2. Manual Installation step 6a/6b (lines 104-106, 119-120):**

In the Quick Reference table, update steps 6a and 6b descriptions:
- Step 6a: Change "Add `jobs:` line to `Procfile.dev`" to "Handled by generator (patches `Procfile.dev`)"
- Step 6b: Change "Add `recurring_schedule` to dispatcher config" to "Handled by generator (patches `config/queue.yml`)"

In the step-by-step details (line 119-120), update the bullet points:
```
   - **Procfile.dev:** If your host uses `bin/dev` (foreman/overmind), add a `jobs:` entry to `Procfile.dev`: `jobs: bundle exec rake solid_queue:start`. Without this, `bin/dev` will not start Solid Queue workers.
   - **Recurring schedule:** Ensure the dispatcher in `config/queue.yml` (or `config/solid_queue.yml`) includes `recurring_schedule: config/recurring.yml`. Without this key, recurring jobs will not load even though the file exists.
```

To:
```
   - **Procfile.dev:** The generator automatically patches `Procfile.dev` with a `jobs:` entry for Solid Queue. Verify the file contains `jobs: bundle exec rake solid_queue:start` after running the generator.
   - **Recurring schedule:** The generator automatically patches `config/queue.yml` dispatchers with `recurring_schedule: config/recurring.yml`. Verify the key is present after running the generator.
```
  </action>
  <verify>
Read the modified file. Confirm: (a) Guided Setup section describes 3 automatic steps (recurring.yml, Procfile.dev, queue dispatcher), (b) manual steps 6a/6b reference generator automation, (c) "re-run" guidance is present, (d) no leftover manual "add this to" instructions for Procfile.dev or queue.yml.
  </verify>
  <done>
docs/setup.md updated to note the generator handles Procfile.dev and queue.yml configuration automatically in both guided and manual sections.
  </done>
</task>
<task type="auto">
  <name>update-troubleshooting-docs</name>
  <files>
    docs/troubleshooting.md
  </files>
  <action>
Update docs/troubleshooting.md issues #4 and #5 to reference generator automation and the RecurringScheduleVerifier.

**Issue #4: Recurring Jobs Not Running (lines 23-35):**

Update to mention running the generator as the primary fix and the RecurringScheduleVerifier for diagnostics:

```
## 4. Recurring Jobs Not Running

- **Symptoms:** Fetch scheduling, scrape scheduling, and cleanup jobs never fire. Sources never auto-fetch on their configured intervals.
- **Primary fix:** Re-run the install generator, which automatically patches the dispatcher config:
  ```bash
  bin/rails generate source_monitor:install
  ```
- **Diagnostics:** Run `bin/source_monitor verify` to check recurring task registration. The RecurringScheduleVerifier will report whether SourceMonitor recurring tasks are loaded into Solid Queue.
- **Manual check:** Verify `config/queue.yml` includes `recurring_schedule: config/recurring.yml` under the `dispatchers:` section. Without this key, Solid Queue's dispatcher will not load the recurring schedule even though `config/recurring.yml` exists.
- **Manual fix (if generator cannot patch):**
  ```yaml
  dispatchers:
    - polling_interval: 1
      batch_size: 500
      recurring_schedule: config/recurring.yml
  ```
```

**Issue #5: Jobs Not Processing with bin/dev (lines 36-44):**

Update to mention running the generator as the primary fix:

```
## 5. Jobs Not Processing with bin/dev

- **Symptoms:** `bin/dev` starts the web server but jobs never run. Running `bin/rails solid_queue:start` manually works fine.
- **Primary fix:** Re-run the install generator, which automatically patches `Procfile.dev`:
  ```bash
  bin/rails generate source_monitor:install
  ```
- **Diagnostics:** Run `bin/source_monitor verify` to check Solid Queue worker status. The SolidQueueVerifier will suggest Procfile.dev if no workers are detected.
- **Manual check:** Verify `Procfile.dev` includes a `jobs:` line:
  ```
  jobs: bundle exec rake solid_queue:start
  ```
- Most Rails 8 apps use foreman or overmind via `bin/dev`. Without a `jobs:` entry, the process manager only starts the web server and asset watchers -- Solid Queue workers are not launched.
```
  </action>
  <verify>
Read the modified file. Confirm: (a) Issue #4 has "Primary fix" mentioning the generator, (b) Issue #4 mentions RecurringScheduleVerifier, (c) Issue #5 has "Primary fix" mentioning the generator, (d) Issue #5 mentions SolidQueueVerifier and Procfile.dev, (e) both issues have "Diagnostics" sections referencing `bin/source_monitor verify`, (f) manual fixes are still present as fallback.
  </verify>
  <done>
docs/troubleshooting.md updated with generator-first remediation, RecurringScheduleVerifier diagnostics, and SolidQueueVerifier Procfile.dev suggestion for issues #4 and #5.
  </done>
</task>
</tasks>
<verification>
1. `grep -n 'performs five actions' .claude/skills/sm-host-setup/SKILL.md` returns a match
2. `grep -n 'Patches Procfile.dev' .claude/skills/sm-host-setup/SKILL.md` returns a match
3. `grep -n 'Patches queue.yml' .claude/skills/sm-host-setup/SKILL.md` returns a match
4. `grep -n 'handled by generator' .claude/skills/sm-host-setup/SKILL.md` returns matches for both checklist items
5. `grep -n 'Automatic' .claude/skills/sm-host-setup/reference/setup-checklist.md` returns matches for Phase 6a and 6b
6. `grep -n 'handled by generator' .claude/skills/sm-host-setup/reference/setup-checklist.md` returns matches for checklist items
7. `grep -n 'RecurringScheduleVerifier' .claude/skills/sm-host-setup/reference/setup-checklist.md` returns a match
8. `grep -n 'recurring_schedule' .claude/skills/sm-configure/SKILL.md` returns a match in the checklist
9. `grep -n 'patches.*queue.yml' .claude/skills/sm-job/SKILL.md` returns a match in the recurring jobs section
10. `grep -n 'generator automatically' docs/setup.md` returns matches in both guided and manual sections
11. `grep -n 'RecurringScheduleVerifier' docs/troubleshooting.md` returns a match in Issue #4
12. `grep -n 'Primary fix' docs/troubleshooting.md` returns matches in Issues #4 and #5
13. No manual "add a jobs: entry to Procfile.dev" instructions remain in any updated file (verified by grep absence)
</verification>
<success_criteria>
- sm-host-setup SKILL.md describes 5 generator actions including Procfile.dev and queue.yml patching (REQ-21)
- sm-host-setup SKILL.md checklist marks Procfile.dev and dispatcher items as auto-handled (REQ-21)
- setup-checklist.md Phase 6a/6b describe generator automation, not manual steps (REQ-21)
- setup-checklist.md references RecurringScheduleVerifier for diagnostics (REQ-21)
- sm-configure SKILL.md checklist references automatic recurring_schedule wiring (REQ-21)
- sm-job SKILL.md recurring jobs section mentions automatic queue.yml patching (REQ-21)
- docs/setup.md guided and manual sections note generator handles Procfile.dev and queue.yml (REQ-21)
- docs/troubleshooting.md Issue #4 recommends generator as primary fix and mentions RecurringScheduleVerifier (REQ-21)
- docs/troubleshooting.md Issue #5 recommends generator as primary fix and mentions SolidQueueVerifier (REQ-21)
- All manual "add this to your file" instructions replaced with "generator handles this" + verification guidance (REQ-21)
</success_criteria>
<output>
.vbw-planning/phases/03-docs-alignment/PLAN-01-SUMMARY.md
</output>
