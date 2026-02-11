---
phase: 1
plan: 2
title: rubocop-audit-and-fix
wave: 2
depends_on: [1]
skills_used: []
must_haves:
  truths:
    - "`bin/rubocop` exits 0 with zero offenses (verified by `bin/rubocop -f simple` output showing `no offenses detected`)"
    - "All existing tests pass (`bin/rails test` exits 0 with no new failures)"
    - "CI lint job would pass (`bin/rubocop -f github` exits 0)"
  artifacts:
    - "All Ruby files in app/, lib/, test/, config/, db/ comply with rubocop-rails-omakase rules"
    - "`.rubocop.yml` may have additional targeted exclusions if auto-generated files legitimately violate rules"
  key_links:
    - "REQ-14 fully satisfied by this plan"
    - "Depends on Plan 01 (frozen_string_literal already resolved -- largest category of violations removed)"
---

# Plan 02: rubocop-audit-and-fix

## Objective

Audit the entire codebase with RuboCop using the `rubocop-rails-omakase` configuration and fix all violations, achieving zero offenses. This satisfies REQ-14 and ensures the CI lint job passes cleanly.

## Context

<context>
@.vbw-planning/REQUIREMENTS.md -- REQ-14: RuboCop audit against omakase ruleset
@.vbw-planning/codebase/CONVENTIONS.md -- Rails omakase style guide, existing patterns
@.rubocop.yml -- inherits from rubocop-rails-omakase, excludes test/dummy/db/schema.rb
@Gemfile -- rubocop-rails-omakase gem included
@bin/rubocop -- wrapper script that forces config path
@.github/workflows/ci.yml -- lint job runs `bin/rubocop -f github`

**Decomposition rationale:** This plan depends on Plan 01 because `Style/FrozenStringLiteralComment` is typically the most voluminous cop violation. By completing Plan 01 first, this plan deals with a much smaller and more varied set of violations that require more careful, contextual fixes.

**Current state:**
- The project uses `rubocop-rails-omakase` as its base ruleset (inherits the gem's rubocop.yml)
- Only one exclusion exists: `test/dummy/db/schema.rb`
- After Plan 01 completes, `Style/FrozenStringLiteralComment` violations will be resolved
- Remaining violations are unknown until the audit is run, but likely categories include:
  - `Style/StringLiterals` (single vs double quotes)
  - `Layout/*` (indentation, spacing, line length)
  - `Metrics/*` (method/class length -- may need exclusions for large files targeted in Phase 3)
  - `Naming/*` (variable/method naming conventions)
  - `Rails/*` cops from the omakase set
- Large files (FeedFetcher 627 lines, Configuration 655 lines, ImportSessionsController 792 lines) may trigger `Metrics/ClassLength` or `Metrics/MethodLength` -- these should be addressed with targeted `.rubocop.yml` exclusions since Phase 3 handles the actual refactoring

**Constraints:**
- Fix violations using RuboCop auto-correct where safe (`rubocop -a` for safe corrections, `-A` for aggressive only when reviewed)
- Do NOT refactor large files to satisfy Metrics cops -- instead exclude them in `.rubocop.yml` with a comment referencing Phase 3
- Preserve all existing behavior -- style-only changes
- The `test/dummy/db/schema.rb` exclusion must remain (Rails-generated)
- Test files in `test/tmp/` are not git-tracked and not subject to RuboCop
</context>

## Tasks

### Task 1: Run RuboCop audit and categorize violations

- **name:** rubocop-audit-categorize-violations
- **files:** (no files modified -- analysis only)
- **action:** Run `bin/rubocop -f json -o tmp/rubocop_report.json` and `bin/rubocop -f simple` to get a complete picture of all violations. Categorize them by: (a) auto-correctable with `-a` (safe), (b) auto-correctable with `-A` (unsafe, needs review), (c) manual fix required, (d) should be excluded (Metrics cops on large files destined for Phase 3 refactoring). Document the count and category of each cop violation type.
- **verify:** The audit report exists and lists all violations. Categorization is complete.
- **done:** Full understanding of the violation landscape. Clear plan for which files need which type of fix.

### Task 2: Apply safe auto-corrections

- **name:** apply-safe-rubocop-autocorrect
- **files:** All Ruby files flagged by RuboCop safe auto-correct
- **action:** Run `bin/rubocop -a` to apply all safe auto-corrections across the codebase. This handles cops like `Style/StringLiterals`, `Layout/TrailingWhitespace`, `Layout/EmptyLineAfterMagicComment`, `Layout/SpaceInsideBlockBraces`, etc. Review the diff to confirm no behavioral changes -- only formatting/style changes. If any auto-correction looks wrong, revert that specific change and handle it manually in Task 3.
- **verify:** Run `git diff --stat` to see scope of changes. Run `bin/rails test` to confirm no test regressions. Run `bin/rubocop -f simple` to see remaining violations after safe auto-correct.
- **done:** All safe auto-correctable violations are fixed. Test suite still passes.

### Task 3: Fix remaining violations manually

- **name:** fix-remaining-rubocop-violations
- **files:** Files with violations that were not auto-correctable or were unsafe auto-corrections
- **action:** For each remaining violation:
  - **Style cops**: Fix manually following the omakase conventions (single quotes for simple strings, double quotes when interpolation needed, etc.)
  - **Layout cops**: Fix indentation, spacing, alignment manually
  - **Naming cops**: Rename variables/methods to comply (ensure test references are updated)
  - **Rails cops**: Fix any Rails-specific violations (e.g., `Rails/HttpPositionalArguments`)
  - If a violation is in a file that is inherently non-compliant due to its nature (e.g., a migration with unusual structure), add a targeted inline `# rubocop:disable` comment with an explanation
- **verify:** Run `bin/rubocop -f simple` after each batch of fixes. The violation count should decrease monotonically. Run `bin/rails test` after all manual fixes.
- **done:** All non-Metrics violations are resolved either by code changes or justified inline disables.

### Task 4: Configure exclusions for large files (Phase 3 targets)

- **name:** configure-rubocop-exclusions-for-phase3
- **files:**
  - `.rubocop.yml`
- **action:** If `Metrics/ClassLength`, `Metrics/MethodLength`, or `Metrics/BlockLength` violations remain for the three large files targeted for refactoring in Phase 3, add targeted exclusions to `.rubocop.yml`:
  ```yaml
  # Phase 3 refactoring targets -- remove exclusions after extraction
  Metrics/ClassLength:
    Exclude:
      - "lib/source_monitor/fetching/feed_fetcher.rb"
      - "lib/source_monitor/configuration.rb"
      - "app/controllers/source_monitor/import_sessions_controller.rb"
  ```
  Add a comment explaining these are temporary exclusions that will be removed in Phase 3. Do NOT exclude any other files -- only the three identified large files.
- **verify:** Run `bin/rubocop` and confirm it exits 0 with zero offenses. The exclusions should only cover the Phase 3 target files.
- **done:** `.rubocop.yml` has targeted, documented exclusions. Zero RuboCop offenses across the entire codebase.

### Task 5: Final validation and CI readiness check

- **name:** validate-rubocop-zero-offenses
- **files:** (no files modified -- validation only)
- **action:** Run the full validation suite: (1) `bin/rubocop -f simple` -- must show `no offenses detected`. (2) `bin/rubocop -f github` -- must exit 0 (this is what CI runs). (3) `bin/rails test` -- full test suite must pass. (4) Verify the coverage baseline has not grown (run `wc -l config/coverage_baseline.json` and confirm it is still approximately 2328 lines -- style changes should not affect coverage).
- **verify:**
  - `bin/rubocop` exits 0
  - `bin/rubocop -f github` exits 0
  - `bin/rails test` exits 0
  - Coverage baseline line count has not increased
- **done:** Zero RuboCop violations. CI-ready. REQ-14 satisfied.

## Verification

1. `bin/rubocop -f simple` outputs `no offenses detected`
2. `bin/rubocop -f github` exits 0 (CI lint format)
3. `bin/rails test` exits 0 with no regressions
4. Coverage baseline (`config/coverage_baseline.json`) has not grown in line count

## Success Criteria

- [x] Zero RuboCop violations against the omakase ruleset (REQ-14)
- [x] Any `.rubocop.yml` exclusions are limited to Phase 3 target files with documenting comments
- [x] CI lint job (`bin/rubocop -f github`) passes
- [x] No test regressions
- [x] No behavioral changes -- all fixes are style/formatting only

## Phase 1 Coverage Note

Phase 1 success criterion #3 ("Coverage baseline shrinks by at least 10%") is not directly addressed by Plans 01 or 02, which focus on code quality (REQ-13, REQ-14). The coverage baseline may shrink slightly if RuboCop fixes remove dead branches or simplify code paths. After Plan 02 completes, regenerate the baseline with `bin/update-coverage-baseline` and measure the delta. The 10% reduction target (from 2328 uncovered lines to ~2095 or fewer) will primarily be achieved in Phase 2 when dedicated test coverage plans execute.
