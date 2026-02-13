# PLAN-01 Summary: procfile-queue-generator-steps

## Status: COMPLETE

## What was done

### Task 1: Add Procfile.dev generator step
- Added `patch_procfile_dev` public method to `InstallGenerator` (between `configure_recurring_jobs` and `print_next_steps`)
- Handles 3 cases: create new file, append to existing, skip if already present
- Added `PROCFILE_JOBS_ENTRY` private constant
- Updated `print_next_steps` with Procfile.dev info message

### Task 2: Add queue.yml dispatcher step
- Added `configure_queue_dispatcher` public method to `InstallGenerator` (between `patch_procfile_dev` and `print_next_steps`)
- Handles 4 cases: missing file, already configured, needs patching, no dispatchers key
- Added private helpers: `queue_config_has_recurring_schedule?`, `add_recurring_schedule_to_dispatchers!`
- Added `RECURRING_SCHEDULE_VALUE` and `DEFAULT_DISPATCHER` private constants

### Task 3: Add 8 generator tests
- 4 Procfile.dev tests: create, append, skip, no-duplicate
- 4 queue.yml tests: patch dispatchers, skip when configured, skip when missing, add default dispatcher
- All 20 generator tests pass (12 existing + 8 new)

### Task 4: Add workflow helpers and integration
- Created `lib/source_monitor/setup/procfile_patcher.rb` (lightweight Pathname-based helper)
- Created `lib/source_monitor/setup/queue_config_patcher.rb` (YAML parsing with recursive dispatcher search)
- Modified `lib/source_monitor/setup/workflow.rb`: added 2 new kwargs, wired into `run` after `initializer_patcher` and before devise check
- Added autoload entries in `lib/source_monitor.rb`
- Updated all 8 workflow tests with new collaborator spies

### Task 5: Full suite verification
- 867 test runs, 2898 assertions, 0 failures, 0 errors
- RuboCop: 376 files, 0 offenses
- Brakeman: 0 warnings

## Files modified
- `lib/generators/source_monitor/install/install_generator.rb` -- 2 new public methods, 4 private helpers/constants
- `test/lib/generators/install_generator_test.rb` -- 8 new tests
- `lib/source_monitor/setup/procfile_patcher.rb` -- NEW
- `lib/source_monitor/setup/queue_config_patcher.rb` -- NEW
- `lib/source_monitor/setup/workflow.rb` -- 2 new kwargs, 2 new patcher calls
- `test/lib/source_monitor/setup/workflow_test.rb` -- added patcher spies to all tests
- `lib/source_monitor.rb` -- 2 new autoload entries

## Commits
1. `af59468` feat(generator): add Procfile.dev patching step to install generator
2. `29250af` feat(generator): add queue.yml dispatcher step to install generator
3. `96365b9` feat(generator): add 8 tests for Procfile.dev and queue.yml steps
4. `4393d17` feat(generator): add workflow helpers and wire patchers into guided install

## Acceptance criteria met
- Generator creates Procfile.dev with web: + jobs: entries when none exists (REQ-16)
- Generator appends jobs: entry to existing Procfile.dev without duplicating (REQ-16)
- Generator skips Procfile.dev when jobs: entry already present (REQ-16 idempotency)
- Generator patches queue.yml dispatchers with recurring_schedule (REQ-17)
- Generator skips queue.yml when recurring_schedule already configured (REQ-17 idempotency)
- Generator handles missing queue.yml gracefully (REQ-17 edge case)
- Guided workflow runs both patchers after generator step (REQ-18)
- All existing tests continue to pass (no regressions)
- 8 new generator tests cover all scenarios
- RuboCop clean, Brakeman clean
