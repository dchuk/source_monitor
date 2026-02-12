# PLAN-01 Summary: skills-docs-alignment

## Status: COMPLETE

## What Was Done

### Task 1: Update sm-host-setup SKILL.md
- Replaced manual Procfile.dev/queue.yml comments (lines 76-80) with automation note and re-run guidance
- Expanded "What the Install Generator Does" from 3 to 5 actions: added Procfile.dev patching and queue.yml dispatcher patching
- Marked Procfile.dev and dispatcher checklist items as `[x]` with "(handled by generator)"
- Added `procfile_patcher.rb` and `queue_config_patcher.rb` to Key Source Files table

### Task 2: Update setup-checklist.md
- Phase 6a renamed to "Procfile.dev for Development (Automatic)" with generator behavior description
- Phase 6b renamed to "Recurring Schedule Dispatcher Wiring (Automatic)" with generator behavior description
- Both sections include verification guidance and "re-run" instructions
- Phase 6b references RecurringScheduleVerifier diagnostics
- Checklist items marked `[x]` with "(handled by generator)"

### Task 3: Update sm-configure and sm-job Skills
- sm-configure SKILL.md: updated queue names checklist entry, added `[x]` dispatcher `recurring_schedule` item
- sm-job SKILL.md: recurring jobs section now mentions automatic `config/queue.yml` patching and idempotency

### Task 4: Update docs/setup.md
- Guided Setup: replaced manual Procfile.dev and queue.yml instructions with 3-bullet automatic summary and re-run guidance
- Manual Installation Quick Reference: steps 6a/6b descriptions changed to "Handled by generator"
- Step-by-step details: Procfile.dev and recurring schedule bullets now describe generator automation with verification guidance

### Task 5: Update docs/troubleshooting.md
- Issue #4 (Recurring Jobs Not Running): added "Primary fix" with generator command, "Diagnostics" with RecurringScheduleVerifier, kept manual fix as fallback
- Issue #5 (Jobs Not Processing with bin/dev): added "Primary fix" with generator command, "Diagnostics" with SolidQueueVerifier Procfile.dev suggestion

## Files Modified
- `.claude/skills/sm-host-setup/SKILL.md` (5-action generator, auto-handled checklist, patcher files in table)
- `.claude/skills/sm-host-setup/reference/setup-checklist.md` (automated Phase 6a/6b, RecurringScheduleVerifier)
- `.claude/skills/sm-configure/SKILL.md` (dispatcher recurring_schedule checklist item)
- `.claude/skills/sm-job/SKILL.md` (automatic queue.yml patching mention)
- `docs/setup.md` (generator automation in guided and manual sections)
- `docs/troubleshooting.md` (generator-first remediation, verifier diagnostics)

## Commit
- `7978d61` docs(03-docs-alignment): update skills and docs for generator automation

## Requirements Satisfied
- REQ-21: All sm-* skills and documentation updated to reflect generator automation of Procfile.dev patching, queue.yml dispatcher wiring, and RecurringScheduleVerifier diagnostics

## Deviations
None. All tasks executed as specified in the plan.
