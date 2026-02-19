---
phase: 2
plan: 4
status: complete
---
# Plan 04 Summary: Switch Default Parallelism to Threads

## Tasks Completed
- [x] Task 1: Switch parallelize to always use `with: :threads` (not just coverage mode)
- [x] Task 2: Add thread-safety comment to reset_configuration! setup block
- [x] Task 3: Verify single-file runs work without PARALLEL_WORKERS=1 (3 files tested, all pass)
- [x] Task 4: Full suite verification (1033 tests, 0 failures, 2 consecutive runs, 0 flaky)

## Commits
- eceb06d: perf(test): switch default parallelism from forks to threads

## Files Modified
- test/test_helper.rb (modified)

## What Was Built
- Unified parallelism to always use `with: :threads` instead of fork-based (forks only used in coverage mode previously)
- Worker count logic preserved: COVERAGE=1 forces 1 worker, otherwise respects SOURCE_MONITOR_TEST_WORKERS env var or defaults to :number_of_processors
- PG fork segfault on single-file runs eliminated — verified with feed_fetcher_success_test.rb, source_test.rb, and sources_controller_test.rb all passing without PARALLEL_WORKERS=1
- Added thread-safety comment explaining why reset_configuration! is safe under thread parallelism
- Note: TestProf emits `before_all is not implemented for parallalization with threads` warning — cosmetic only, before_all works correctly since single-file runs stay below parallelization threshold and full suite distributes by class

## Deviations
- None
