---
phase: "02"
plan: "04"
title: "Switch Default Parallelism to Threads"
wave: 2
depends_on: ["PLAN-01"]
must_haves:
  - "REQ-PERF-04: Default parallelism switched from forks to threads"
  - "test_helper.rb parallelize call uses 'with: :threads' for all modes"
  - "Thread safety verified for reset_configuration! (no data races)"
  - "All 1031+ tests pass with thread-based parallelism"
  - "PG fork segfault on single-file runs eliminated"
  - "PARALLEL_WORKERS env var still respected"
  - "RuboCop zero offenses on modified files"
skills_used: []
---

# Plan 04: Switch Default Parallelism to Threads

## Objective

Switch the default test parallelism from fork-based to thread-based. This eliminates the PG fork segfault that forces `PARALLEL_WORKERS=1` on single-file runs, and enables the FeedFetcherTest split (Plan 01) to actually parallelize across workers. Thread-based parallelism is already proven working in coverage mode (`COVERAGE=1`).

## Context

- `@` `test/test_helper.rb` -- current parallelism configuration (forks by default, threads only for coverage)
- `@` `.vbw-planning/phases/02-test-performance/02-RESEARCH.md` -- research confirming thread parallelism works in coverage mode
- `@` `test/test_prof.rb` -- TestProf setup (thread-compatible)

**Rationale:** The current code uses `parallelize(workers: worker_count)` which defaults to fork-based parallelism. This causes PG segfaults on single-file runs and prevents the FeedFetcherTest split from distributing across workers (since forks copy the process and the PG connection). Thread-based parallelism is already proven (used with COVERAGE=1) and avoids these issues.

**Dependency on Plan 01:** Plan 01 splits FeedFetcherTest into 6+ classes. Without the split, thread parallelism still cannot distribute the 71-test monolith across workers. The split must complete first for the parallelism switch to realize its full benefit.

**Risk: Thread safety of `reset_configuration!`** -- The global `setup` block calls `SourceMonitor.reset_configuration!` before every test. With threads, multiple tests may call this simultaneously. Since `reset_configuration!` replaces the entire `@configuration` instance, and each test reads config after setup, this is safe as long as no test modifies config mid-test while another test is reading it. The research confirmed this is pure Ruby assignment (microseconds). If any flaky failures appear, we add a `Mutex` around the reset.

## Tasks

### Task 1: Switch parallelize to threads

In `test/test_helper.rb`, replace the parallelism block:

```ruby
# BEFORE:
if ENV["COVERAGE"]
  parallelize(workers: 1, with: :threads)
else
  worker_count = ENV.fetch("SOURCE_MONITOR_TEST_WORKERS", :number_of_processors)
  worker_count = worker_count.to_i if worker_count.is_a?(String) && !worker_count.empty?
  worker_count = :number_of_processors if worker_count.respond_to?(:zero?) && worker_count.zero?
  parallelize(workers: worker_count)
end
```

```ruby
# AFTER:
worker_count = if ENV["COVERAGE"]
  1
else
  count = ENV.fetch("SOURCE_MONITOR_TEST_WORKERS", :number_of_processors)
  count = count.to_i if count.is_a?(String) && !count.empty?
  count = :number_of_processors if count.respond_to?(:zero?) && count.zero?
  count
end
parallelize(workers: worker_count, with: :threads)
```

Key change: Always use `with: :threads` (not just for coverage). Worker count logic stays the same.

### Task 2: Add thread-safety comment to reset_configuration

Add a comment in the `setup` block explaining thread safety:

```ruby
setup do
  # Thread-safe: reset_configuration! replaces @configuration atomically.
  # Each test gets a fresh config object. No concurrent mutation risk since
  # tests read config only after their own setup completes.
  SourceMonitor.reset_configuration!
end
```

### Task 3: Verify single-file runs work without PARALLEL_WORKERS=1

The main benefit of thread-based parallelism: single-file runs no longer segfault.

```bash
# These should now work WITHOUT PARALLEL_WORKERS=1
bin/rails test test/lib/source_monitor/fetching/feed_fetcher_success_test.rb
bin/rails test test/models/source_monitor/source_test.rb
bin/rails test test/controllers/source_monitor/sources_controller_test.rb
```

### Task 4: Full suite verification

```bash
# Full suite with thread parallelism
bin/rails test

# Verify worker count is respected
SOURCE_MONITOR_TEST_WORKERS=4 bin/rails test

# Lint
bin/rubocop test/test_helper.rb
```

Ensure all 1031+ tests pass with zero failures. Watch for flaky tests that might indicate thread-safety issues. If any test fails intermittently, check if it modifies global state (module-level variables, class variables, or singletons) and fix the isolation.

## Files

| Action | Path |
|--------|------|
| MODIFY | `test/test_helper.rb` |

## Verification

```bash
# Single-file run (no PARALLEL_WORKERS=1 needed)
bin/rails test test/models/source_monitor/source_test.rb

# Full suite
bin/rails test

# Lint
bin/rubocop test/test_helper.rb
```

## Success Criteria

- `grep "with: :threads" test/test_helper.rb` shows the threads configuration
- `bin/rails test` passes all 1031+ tests
- Single-file runs work without PARALLEL_WORKERS=1 workaround
- No flaky test failures in 2 consecutive full suite runs
- Full suite completes in <70s locally (down from 133s)
