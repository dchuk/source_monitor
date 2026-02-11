# Contributing Guidelines

This project ships each roadmap slice behind a fast, reliable test loop. The notes below summarize the expectations for day-to-day development and code review.

## Test Suite Expectations

- **Fast feedback:** run `bundle exec rake app:test:smoke` for unit, helper, and job coverage before pushing. Use `PARALLEL_WORKERS=1` locally when profiling failures for determinism.
- **Full validation:** continue to run `bundle exec rails test` (or `bin/test-coverage` in CI) before marking a slice ready for review.
- **Background jobs:** the default adapter is `:test`. Switch to inline execution only for the precise block that needs it via `with_inline_jobs { ... }`; never flip the global adapter.
- **Database usage:** prefer transactional fixtures over manual `delete_all`. Reach for `setup_once` (TestProf’s `before_all`) when immutable data can be shared safely across examples.
- **System tests:** keep them focused on UI workflows. If a test only exercises server logic, convert it to a controller/lib test. Stub external services and avoid long flows.

## Performance Profiling

- **Local commands:**
  - `TAG_PROF=type PARALLEL_WORKERS=1 bundle exec rails test`
  - `EVENT_PROF=sql.active_record PARALLEL_WORKERS=1 bundle exec rails test`
  - `TEST_STACK_PROF=1 PARALLEL_WORKERS=1 bundle exec rails test test/integration`
- **CI automation:** a scheduled `profiling` workflow runs the commands above nightly, archives `tmp/test_prof`, and applies guardrails via `bin/check-test-prof-metrics` (suite ≤ 80s, integration ≤ 35s, DB time ≤ 5s). Failures block the job so regressions surface quickly.

## Code Review Checklist

Before approval, verify that the changes:

1. Avoid unnecessary database persistence (test doubles over `.create` when assertions allow).
2. Share heavy setup with `setup_once` or helper memoization instead of per-test rebuilds.
3. Scope inline job execution to `with_inline_jobs { ... }` blocks—no suite-wide adapter swaps.
4. Keep new or modified system specs lean, relying on lower-level coverage when UI is not essential.
5. Include updates to smoke/full-test instructions or profiling docs when new flows require them.

Thanks for keeping the suite fast and predictable. Profile early and often, and treat the guardrails as hard limits when reviewing new slices.
