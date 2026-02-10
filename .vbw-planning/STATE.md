<!-- VBW STATE TEMPLATE (ARTF-05) -- Session dashboard, auto-updated -->
<!-- Updated after each plan completion and at checkpoints -->

# Project State

## Project Reference

See: .vbw-planning/PROJECT.md (updated 2026-02-09)

**Core value:** Drop-in Rails engine for feed monitoring, content scraping, and operational dashboards.
**Current focus:** Phase 3 - Large File Refactoring

## Current Position

Phase: 3 of 4 (Large File Refactoring)
Plan: 0 of 4 in current phase
Status: Ready to plan
Last activity: 2026-02-09 -- Phase 2 complete (5/5 plans done)

Progress: [#####.....] 54%

## Codebase Profile

- **Total source files:** 530
- **Primary language:** Ruby (325 files)
- **Templates:** ERB (48 files)
- **Tests:** 131 test files detected
- **Test suite:** 760 runs, 2626 assertions, 0 failures (up from 473 runs in Phase 1)
- **CI/CD:** GitHub Actions (1 workflow)
- **Docker:** Yes (2 files)
- **Monorepo:** No
- **Stack:** Ruby on Rails 8 engine, Solid Queue, Hotwire, Tailwind CSS, PostgreSQL, Minitest, RuboCop, Brakeman

## Accumulated Context

### Decisions

- [bootstrap]: Focus on coverage + refactoring before new features
- [bootstrap]: Keep PostgreSQL-only for now
- [bootstrap]: Keep host-app auth model
- [phase-1]: Omakase RuboCop config only enables 45/775 cops; all Metrics cops disabled
- [phase-1]: No .rubocop.yml exclusions needed for large files (Metrics cops off)
- [phase-2]: PG parallel fork segfault when running single test files; use PARALLEL_WORKERS=1 or full suite
- [phase-2]: Configuration tests (Plan 03) were committed under mislabeled "dev-plan05" commit; corrected in summaries

### Pending Todos

None

### Blockers/Concerns

None

### Skills

**Installed:**
- agent-browser (global)
- flowdeck (global)
- ralph-tui-create-json (global)
- ralph-tui-prd (global)
- vastai (global)
- find-skills (global)

**Suggested (not installed):**
- dhh-rails-style (registry) -- DHH-style Rails conventions
- ruby-rails (registry) -- Ruby on Rails development
- github-actions (registry) -- GitHub Actions workflow

**Stack detected:** Ruby on Rails 8 engine, Solid Queue, Hotwire (Turbo + Stimulus), Tailwind CSS, PostgreSQL, ESLint, GitHub Actions, Minitest, RuboCop, Brakeman
**Registry available:** yes

## Session Continuity

Last session: 2026-02-09
Stopped at: Phase 2 complete, ready for Phase 3 planning
Resume file: none
