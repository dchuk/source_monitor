---
phase: 4
plan: 3
title: final-verification
wave: 2
depends_on:
  - "plan-01 (conventions-audit)"
  - "plan-02 (item-creator-extraction)"
skills_used: []
cross_phase_deps:
  - "Phase 1 -- coverage baseline established at 2117 uncovered lines across 105 files"
  - "Phase 2 -- critical path test coverage added (500+ uncovered lines expected to be covered)"
  - "Phase 3 -- large file refactoring (new files created, some lines shifted between files)"
must_haves:
  truths:
    - "Running `bin/rails test` exits 0 with 760+ runs and 0 failures"
    - "Running `bin/rubocop -f simple` shows `no offenses detected`"
    - "Running `bin/brakeman --no-pager -q` exits 0 with zero warnings"
    - "The regenerated `config/coverage_baseline.json` has at most 847 uncovered lines (60% reduction from 2117)"
    - "No file in app/ or lib/ exceeds 300 lines"
  artifacts:
    - "config/coverage_baseline.json -- regenerated with current coverage data"
  key_links:
    - "Phase 4 success criterion #1 -- all models, controllers, service objects follow conventions"
    - "Phase 4 success criterion #2 -- zero RuboCop violations"
    - "Phase 4 success criterion #3 -- coverage baseline at least 60% smaller than original"
    - "Phase 4 success criterion #4 -- CI pipeline fully green"
---

# Plan 03: final-verification

## Objective

Regenerate the coverage baseline to reflect all test improvements from Phases 2-4, verify the 60% reduction target is met, run full CI-equivalent checks (tests, RuboCop, Brakeman), and confirm no file exceeds 300 lines. This plan is the final gate before Phase 4 (and the entire VBW roadmap) can be marked complete.

## Context

<context>
@config/coverage_baseline.json -- Currently shows 2117 uncovered lines across 105 files. This baseline has NOT been regenerated since Phase 1. Phases 2 and 3 added significant test coverage (Phase 2 targeted ~630 lines directly plus indirect coverage, Phase 3 refactored files which shifted coverage around). The actual current uncovered count should be significantly lower.

@bin/update-coverage-baseline -- Script that regenerates the baseline from SimpleCov results. Requires running the test suite with coverage first (`COVERAGE=1 bin/rails test` or `bin/test-coverage`).

@bin/check-diff-coverage -- CI script that checks diff coverage against the baseline.

@AGENTS.md -- Documents the workflow: "refresh config/coverage_baseline.json by running bin/test-coverage followed by bin/update-coverage-baseline"

@test/test_helper.rb -- Coverage is enabled when `CI` or `COVERAGE` env var is set. Uses SimpleCov with branch coverage.

**60% reduction target:** The original baseline has 2117 uncovered lines. A 60% reduction means the new baseline must have at most 847 uncovered lines (2117 * 0.4 = 847). Phase 2 directly targeted ~630 lines in top files, and indirect coverage should bring more. If the target is not met, this task must identify the gap and either add targeted tests or document which files still need coverage.

**CI-equivalent checks:**
- `bin/rubocop -f github` (lint job)
- `bin/brakeman --no-pager` (security job)
- `bin/rails test` (test job)
- diff coverage check (test job)
</context>

## Tasks

### Task 1: Regenerate coverage baseline

- **name:** regenerate-coverage-baseline
- **files:**
  - `config/coverage_baseline.json`
- **action:** Run the full test suite with coverage enabled: `COVERAGE=1 bin/rails test`. Then regenerate the baseline: `bin/update-coverage-baseline`. Compare the new uncovered line count to the original 2117. The target is at most 847 uncovered lines (60% reduction). If the target is met, commit the regenerated baseline. If not, document the gap and identify which files still have the most uncovered lines for targeted fix in Task 2.
- **verify:** `ruby -rjson -e 'data = JSON.parse(File.read("config/coverage_baseline.json")); total = data.values.map(&:size).sum; puts "Uncovered: #{total}"; exit(total <= 847 ? 0 : 1)'` exits 0
- **done:** Coverage baseline regenerated. Uncovered line count documented.

### Task 2: Address coverage gap if target not met

- **name:** address-coverage-gap
- **files:**
  - Test files as needed (determined by Task 1 gap analysis)
  - `config/coverage_baseline.json` (re-regenerate after adding tests)
- **action:** If Task 1 shows the 60% reduction target is NOT met, analyze the regenerated baseline to find the largest remaining gaps. Add targeted tests for the top uncovered files until the 847-line target is met. Focus on files with the most uncovered lines that are NOT in the `:nocov:` exclusion zones. After adding tests, re-run `COVERAGE=1 bin/rails test` and `bin/update-coverage-baseline` to verify. If the target IS already met from Task 1, this task is a no-op -- simply verify and move on.
- **verify:** `ruby -rjson -e 'data = JSON.parse(File.read("config/coverage_baseline.json")); total = data.values.map(&:size).sum; puts "Uncovered: #{total}"; exit(total <= 847 ? 0 : 1)'` exits 0
- **done:** Coverage baseline meets 60% reduction target (at most 847 uncovered lines).

### Task 3: Run full CI-equivalent verification

- **name:** full-ci-verification
- **files:** (no modifications -- verification only)
- **action:** Run all CI-equivalent checks in sequence:
  1. `bin/rubocop -f simple` -- must show `no offenses detected`
  2. `bin/brakeman --no-pager -q` -- must exit 0 with zero warnings
  3. `bin/rails test` -- must exit 0 with 760+ runs and 0 failures
  4. Verify no file in app/ or lib/ exceeds 300 lines: `find app lib -name '*.rb' -exec wc -l {} + | sort -rn | awk '$1 > 300 && $2 != "total" {print; found=1} END {exit found ? 1 : 0}'`
  5. Verify all models have `frozen_string_literal: true`: `grep -rL 'frozen_string_literal: true' app/models/source_monitor/*.rb` returns empty
  6. Verify all controllers have `frozen_string_literal: true`: `grep -rL 'frozen_string_literal: true' app/controllers/source_monitor/*.rb` returns empty

  Document any failures and fix them before marking this task done.
- **verify:** All 6 checks above pass
- **done:** All CI-equivalent checks pass. Codebase fully clean.

### Task 4: Final conventions spot-check

- **name:** final-conventions-spot-check
- **files:** (read-only audit, fix only if issues found)
- **action:** Do a final walkthrough of all models, controllers, and service objects checking:
  - All models use `ModelExtensions.register(self, :key)` (except ApplicationRecord)
  - All models have appropriate validations for their associations
  - All service objects follow the `initialize`/`call` pattern or `self.call` class method
  - All jobs inherit from ApplicationJob and use `source_monitor_queue`
  - All concerns use `extend ActiveSupport::Concern` and `included do...end`
  - No commented-out code blocks remain
  - No TODO/FIXME/HACK comments without associated tracking
  - All Struct definitions use `keyword_init: true`

  Fix any issues found. This should be a light pass since most conventions were already followed.
- **verify:** `bin/rails test` exits 0 AND `bin/rubocop -f simple` shows `no offenses detected`
- **done:** All conventions verified. Codebase passes final quality gate.

## Verification

1. `bin/rails test` exits 0 with 760+ runs and 0 failures
2. `bin/rubocop -f simple` shows `no offenses detected`
3. `bin/brakeman --no-pager -q` exits 0
4. Coverage baseline has at most 847 uncovered lines
5. No Ruby file in app/ or lib/ exceeds 300 lines
6. All frozen_string_literal pragmas present

## Success Criteria

- [ ] Coverage baseline regenerated and at most 847 uncovered lines (60% reduction from 2117)
- [ ] Zero RuboCop violations
- [ ] Zero Brakeman warnings
- [ ] All 760+ tests pass with 0 failures
- [ ] No file in app/ or lib/ exceeds 300 lines
- [ ] All conventions verified in final spot-check
- [ ] Phase 4 complete -- all ROADMAP success criteria met
