---
phase: 1
plan: 1
title: frozen-string-literal-audit
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Every git-tracked `.rb` file begins with `# frozen_string_literal: true` as its first line (verified by `git ls-files -- '*.rb' | xargs head -1 | grep -cv 'frozen_string_literal: true'` returning 0)"
    - "`bin/rubocop --only Style/FrozenStringLiteralComment` exits 0 with zero offenses"
    - "All existing tests pass (`bin/rails test` exits 0)"
  artifacts:
    - "98 Ruby files modified to add the `# frozen_string_literal: true` pragma"
  key_links:
    - "REQ-13 fully satisfied by this plan"
---

# Plan 01: frozen-string-literal-audit

## Objective

Add the `# frozen_string_literal: true` magic comment to every git-tracked Ruby file that is currently missing it. This is a mechanical, low-risk change that brings the codebase into full compliance with REQ-13 and prepares for the RuboCop audit in Plan 02.

## Context

<context>
@.vbw-planning/REQUIREMENTS.md -- REQ-13: frozen_string_literal consistency
@.vbw-planning/codebase/CONVENTIONS.md -- documents existing frozen_string_literal convention
@.rubocop.yml -- RuboCop configuration (omakase base)

**Decomposition rationale:** This plan is separated from the RuboCop audit because (a) frozen_string_literal changes touch nearly 100 files and are purely mechanical, making them ideal for a single focused commit, and (b) completing this first removes a large category of RuboCop violations, simplifying Plan 02's scope.

**Current state:**
- 325 git-tracked Ruby files total
- 227 already have `# frozen_string_literal: true`
- 98 are missing it
- Missing files span: app/ (5), lib/ (24 including setup/, engine, version, assets), test/ (43 non-dummy test files), test/dummy/ (22), config/ (1), db/migrate/ (4)
- The codebase convention (per CONVENTIONS.md) is to use frozen_string_literal consistently, but it has drifted in setup/, engine infrastructure, test files, and dummy app files

**Constraints:**
- Do NOT modify files under `test/tmp/` (generated artifacts, not tracked in git)
- The `test/lib/tmp/install_generator/config/initializers/source_monitor.rb` already has the pragma (verified)
- Migration files and config/routes.rb need the pragma too
- Some files may have a shebang line (`#!/usr/bin/env ruby`) as line 1 -- the pragma must go AFTER the shebang
- `test/dummy/db/schema.rb` is excluded from RuboCop in `.rubocop.yml` but should still get the pragma for consistency
</context>

## Tasks

### Task 1: Add frozen_string_literal to app/ and lib/ source files

- **name:** add-frozen-pragma-to-source-files
- **files:**
  - `app/controllers/source_monitor/application_controller.rb`
  - `app/controllers/source_monitor/health_controller.rb`
  - `app/helpers/source_monitor/application_helper.rb`
  - `app/jobs/source_monitor/application_job.rb`
  - `app/models/source_monitor/application_record.rb`
  - `lib/source_monitor.rb`
  - `lib/source_monitor/assets.rb`
  - `lib/source_monitor/assets/bundler.rb`
  - `lib/source_monitor/engine.rb`
  - `lib/source_monitor/version.rb`
  - `lib/source_monitor/setup/initializer_patcher.rb`
  - `lib/source_monitor/setup/bundle_installer.rb`
  - `lib/source_monitor/setup/workflow.rb`
  - `lib/source_monitor/setup/gemfile_editor.rb`
  - `lib/source_monitor/setup/requirements.rb`
  - `lib/source_monitor/setup/detectors.rb`
  - `lib/source_monitor/setup/shell_runner.rb`
  - `lib/source_monitor/setup/cli.rb`
  - `lib/source_monitor/setup/verification/printer.rb`
  - `lib/source_monitor/setup/verification/telemetry_logger.rb`
  - `lib/source_monitor/setup/verification/solid_queue_verifier.rb`
  - `lib/source_monitor/setup/verification/result.rb`
  - `lib/source_monitor/setup/verification/action_cable_verifier.rb`
  - `lib/source_monitor/setup/verification/runner.rb`
  - `lib/source_monitor/setup/install_generator.rb`
  - `lib/source_monitor/setup/dependency_checker.rb`
  - `lib/source_monitor/setup/prompter.rb`
  - `lib/source_monitor/setup/migration_installer.rb`
  - `lib/source_monitor/setup/node_installer.rb`
- **action:** Prepend `# frozen_string_literal: true\n\n` to each file listed above. If the file already begins with a shebang (`#!`), insert the pragma on line 2 (after the shebang) with a blank line separating them. For `lib/source_monitor.rb` specifically, note it starts with `require` statements -- the pragma goes before all requires.
- **verify:** Run `grep -cL 'frozen_string_literal: true' app/**/*.rb lib/**/*.rb` returns no results (all files have the pragma). Additionally run `ruby -c lib/source_monitor.rb` to confirm syntax validity.
- **done:** All 29 app/ and lib/ Ruby files have `# frozen_string_literal: true` as their first non-shebang line.

### Task 2: Add frozen_string_literal to config and migration files

- **name:** add-frozen-pragma-to-config-and-migrations
- **files:**
  - `config/routes.rb`
  - `db/migrate/20251009103000_add_feed_content_readability_to_sources.rb`
  - `db/migrate/20251014171659_add_performance_indexes.rb`
  - `db/migrate/20251014172525_add_fetch_status_check_constraint.rb`
  - `db/migrate/20251108120116_refresh_fetch_status_constraint.rb`
- **action:** Prepend `# frozen_string_literal: true\n\n` to each file. These are small files (migration class definitions and route definitions).
- **verify:** Run `head -1` on each file to confirm the pragma is present. Run `ruby -c config/routes.rb` to confirm syntax validity (it will fail since it references SourceMonitor::Engine, so instead just visually confirm the pragma is on line 1).
- **done:** All 5 config/ and db/migrate/ files have the pragma.

### Task 3: Add frozen_string_literal to test files (excluding test/dummy and test/tmp)

- **name:** add-frozen-pragma-to-test-files
- **files:**
  - `test/test_helper.rb`
  - `test/source_monitor_test.rb`
  - `test/gemspec_test.rb`
  - `test/application_system_test_case.rb`
  - `test/system/dropdown_fallback_test.rb`
  - `test/integration/engine_mounting_test.rb`
  - `test/integration/navigation_test.rb`
  - `test/controllers/source_monitor/health_controller_test.rb`
  - `test/jobs/source_monitor/fetch_feed_job_test.rb`
  - `test/jobs/source_monitor/item_cleanup_job_test.rb`
  - `test/jobs/source_monitor/log_cleanup_job_test.rb`
  - All files under `test/lib/source_monitor/setup/` (12 files)
  - All files under `test/lib/source_monitor/setup/verification/` (5 files)
  - `test/lib/source_monitor/instrumentation_test.rb`
  - `test/lib/source_monitor/feedjira_configuration_test.rb`
  - `test/lib/source_monitor/metrics_test.rb`
  - `test/lib/source_monitor/scheduler_test.rb`
  - `test/lib/source_monitor/release/runner_test.rb`
  - `test/lib/source_monitor/release/changelog_test.rb`
  - `test/lib/source_monitor/items/item_creator_test.rb`
  - `test/lib/source_monitor/items/retention_pruner_test.rb`
  - `test/lib/source_monitor/events/event_system_test.rb`
  - `test/lib/source_monitor/assets/bundler_test.rb`
  - `test/lib/source_monitor/engine_assets_configuration_test.rb`
  - `test/lib/source_monitor/http_test.rb`
  - `test/lib/source_monitor/fetching/feed_fetcher_test.rb`
  - `test/lib/source_monitor/fetching/fetch_runner_test.rb`
- **action:** Prepend `# frozen_string_literal: true\n\n` to each file. The `test/test_helper.rb` file may have a shebang or special first lines -- check and handle accordingly.
- **verify:** Run `find test -name '*.rb' -not -path 'test/tmp/*' -not -path 'test/dummy/*' -exec head -1 {} \; | grep -cv 'frozen_string_literal'` returns 0.
- **done:** All 43 test files (excluding dummy and tmp) have the pragma.

### Task 4: Add frozen_string_literal to test/dummy files

- **name:** add-frozen-pragma-to-dummy-app
- **files:**
  - `test/dummy/app/controllers/application_controller.rb`
  - `test/dummy/app/controllers/test_support_controller.rb`
  - `test/dummy/app/helpers/application_helper.rb`
  - `test/dummy/app/jobs/application_job.rb`
  - `test/dummy/app/mailers/application_mailer.rb`
  - `test/dummy/app/models/application_record.rb`
  - `test/dummy/app/models/user.rb`
  - `test/dummy/config/application.rb`
  - `test/dummy/config/boot.rb`
  - `test/dummy/config/environment.rb`
  - `test/dummy/config/environments/development.rb`
  - `test/dummy/config/environments/production.rb`
  - `test/dummy/config/environments/test.rb`
  - `test/dummy/config/importmap.rb`
  - `test/dummy/config/puma.rb`
  - `test/dummy/config/routes.rb`
  - `test/dummy/config/initializers/assets.rb`
  - `test/dummy/config/initializers/content_security_policy.rb`
  - `test/dummy/config/initializers/filter_parameter_logging.rb`
  - `test/dummy/config/initializers/inflections.rb`
  - `test/dummy/db/migrate/20251124080000_create_users.rb`
  - `test/dummy/db/schema.rb`
- **action:** Prepend `# frozen_string_literal: true\n\n` to each file. The `test/dummy/db/schema.rb` may be auto-generated by Rails -- still add the pragma since it is git-tracked and part of the project.
- **verify:** Run `find test/dummy -name '*.rb' -exec head -1 {} \; | grep -cv 'frozen_string_literal'` returns 0.
- **done:** All 22 dummy app Ruby files have the pragma.

### Task 5: Validate full codebase compliance and run tests

- **name:** validate-frozen-pragma-compliance
- **files:** (no files modified -- validation only)
- **action:** Run three verification commands: (1) Count git-tracked Ruby files without the pragma -- must be 0. (2) Run `bin/rubocop --only Style/FrozenStringLiteralComment` to confirm zero RuboCop offenses for this cop. (3) Run the test suite to confirm no regressions from adding the pragma.
- **verify:**
  - `git ls-files -- '*.rb' | xargs head -1 | grep -cv 'frozen_string_literal: true'` outputs `0`
  - `bin/rubocop --only Style/FrozenStringLiteralComment` exits 0
  - `bin/rails test` exits 0 (or at minimum no new failures)
- **done:** Full codebase compliance confirmed. REQ-13 is satisfied.

## Verification

1. `git ls-files -- '*.rb' | xargs head -1 | grep -cv 'frozen_string_literal: true'` returns `0`
2. `bin/rubocop --only Style/FrozenStringLiteralComment` exits 0 with zero offenses
3. Test suite passes with no regressions

## Success Criteria

- [x] Every git-tracked Ruby file has `# frozen_string_literal: true` (REQ-13)
- [x] RuboCop `Style/FrozenStringLiteralComment` cop passes with zero offenses
- [x] No test regressions introduced
