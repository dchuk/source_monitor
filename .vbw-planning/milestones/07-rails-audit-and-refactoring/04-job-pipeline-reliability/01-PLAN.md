---
phase: "04"
plan: "01"
title: "Extract FetchFeedJob Retry Orchestrator Service"
wave: 1
depends_on: []
skills_used:
  - sm-job
  - sm-pipeline-stage
  - tdd-cycle
must_haves:
  - "New RetryOrchestrator service at lib/source_monitor/fetching/retry_orchestrator.rb with Result pattern"
  - "RetryOrchestrator.call accepts source, error, decision args and returns Result(:retry_enqueued | :circuit_opened | :exhausted)"
  - "FetchFeedJob reduced to shallow delegation -- no handle_transient_error, enqueue_retry!, open_circuit!, reset_retry_state! methods"
  - "FetchFeedJob delegates retry orchestration to RetryOrchestrator after getting RetryPolicy decision"
  - "RetryOrchestrator test file at test/lib/source_monitor/fetching/retry_orchestrator_test.rb covers retry, circuit-open, and exhausted paths"
  - "Existing FetchFeedJob tests still pass (behavior unchanged, only extraction)"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 01: Extract FetchFeedJob Retry Orchestrator Service

## Objective

Extract ~60 lines of retry/circuit-breaker execution logic from FetchFeedJob into a dedicated `Fetching::RetryOrchestrator` service (S2). This makes retry logic independently testable and keeps the job shallow per engine conventions.

## Context

- @.claude/skills/sm-job/SKILL.md -- Job conventions (shallow delegation, ID args, source_monitor_queue)
- @.claude/skills/sm-pipeline-stage/SKILL.md -- Pipeline architecture and error handling patterns
- @.claude/skills/tdd-cycle/SKILL.md -- TDD red-green-refactor workflow
- `app/jobs/source_monitor/fetch_feed_job.rb` (147 lines) contains `handle_transient_error`, `enqueue_retry!`, `open_circuit!`, `reset_retry_state!` methods that mix job concerns with domain logic
- `lib/source_monitor/fetching/retry_policy.rb` (90 lines) already makes retry decisions via Decision struct -- RetryOrchestrator will execute those decisions
- Existing Result pattern in FeedFetcher, ItemCreator, Enqueuer provides the model to follow

## Tasks

### Task 1: Write RetryOrchestrator tests (TDD red)

Create `test/lib/source_monitor/fetching/retry_orchestrator_test.rb`:
- Test `call` with retry decision: updates source state (fetch_retry_attempt, next_fetch_at, fetch_status), enqueues FetchFeedJob with wait
- Test `call` with circuit-open decision: updates source (fetch_circuit_opened_at, fetch_circuit_until, fetch_status to failed), does NOT enqueue retry
- Test `call` with exhausted decision (neither retry nor circuit): resets retry state on source, returns exhausted status
- Test atomic source updates use `with_lock`
- Use `create_source!` factory, mock RetryPolicy decision structs

### Task 2: Implement RetryOrchestrator service

Create `lib/source_monitor/fetching/retry_orchestrator.rb`:
- Class `SourceMonitor::Fetching::RetryOrchestrator`
- `Result = Struct.new(:status, :source, :error, :decision, keyword_init: true)` with `retry_enqueued?`, `circuit_opened?`, `exhausted?` helpers
- `.call(source:, error:, decision:, job_class: SourceMonitor::FetchFeedJob, now: Time.current)` class method
- Extract `enqueue_retry!`, `open_circuit!`, `reset_retry_state!` logic from FetchFeedJob
- All source state updates wrapped in `source.with_lock { source.reload; source.update!(...) }`
- Add autoload declaration in `lib/source_monitor.rb` under the Fetching namespace

### Task 3: Refactor FetchFeedJob to use RetryOrchestrator

Modify `app/jobs/source_monitor/fetch_feed_job.rb`:
- Remove `handle_transient_error`, `enqueue_retry!`, `open_circuit!`, `reset_retry_state!` methods
- In `handle_transient_error` call site, replace with:
  ```ruby
  decision = RetryPolicy.new(source:, error:, now: Time.current).decision
  return raise error unless decision
  result = RetryOrchestrator.call(source:, error:, decision:)
  raise error if result.exhausted?
  ```
- Keep `handle_concurrency_error` in the job (it's concurrency-specific, not retry-policy)
- Target: job should be ~80 lines

### Task 4: Update FetchFeedJob tests

Update `test/jobs/source_monitor/fetch_feed_job_test.rb`:
- Replace tests that directly tested retry state updates with tests that verify RetryOrchestrator is called
- Keep integration-level tests that verify end-to-end behavior (fetch failure -> source state updated)
- Ensure existing test coverage is maintained, not reduced

### Task 5: Verify

- `bin/rails test test/lib/source_monitor/fetching/retry_orchestrator_test.rb` -- all pass
- `bin/rails test test/jobs/source_monitor/fetch_feed_job_test.rb` -- all pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
