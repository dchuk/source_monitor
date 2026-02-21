---
phase: "02"
plan: "02"
title: "Log Level Reduction and Integration Test Tagging"
wave: 1
depends_on: []
must_haves:
  - "REQ-PERF-02: config.log_level = :warn in test/dummy/config/environments/test.rb"
  - "REQ-PERF-03: Integration tests tagged so --exclude-pattern can skip them"
  - "host_install_flow_test.rb and release_packaging_test.rb moved under test/integration/"
  - "bin/rails test --exclude-pattern='**/integration/**' excludes slow integration tests"
  - "bin/rails test runs all tests including integration (default behavior preserved)"
  - "RuboCop zero offenses on modified files"
skills_used: []
---

# Plan 02: Log Level Reduction and Integration Test Tagging

## Objective

Two quick wins that reduce test wall-clock time: (1) eliminate 95MB of debug log IO by setting test log level to `:warn` (saves 5-15s), and (2) ensure integration tests are organized under `test/integration/` so developers can exclude the 31s of subprocess-spawning tests during iterative development using `--exclude-pattern`.

## Context

- `@` `test/dummy/config/environments/test.rb` -- currently has no explicit log_level (defaults to :debug)
- `@` `test/integration/host_install_flow_test.rb` -- slow integration test (subprocess spawning, ~15s)
- `@` `test/integration/release_packaging_test.rb` -- slow integration test (gem build + subprocess, ~15s)
- `@` `test/integration/engine_mounting_test.rb` -- fast integration test (route checks)
- `@` `test/integration/navigation_test.rb` -- empty placeholder test
- `@` `test/test_helper.rb` -- contains DEFAULT_TEST_EXCLUDE but does NOT need modification

**Rationale:** The research found 95MB of :debug log output during tests. Setting :warn eliminates this IO without losing any test coverage. Integration tests already live under `test/integration/` -- we just need to verify the exclude pattern works and document it.

## Tasks

### Task 1: Set test log level to :warn

In `test/dummy/config/environments/test.rb`, add after the `config.cache_store = :null_store` line:

```ruby
# Reduce log IO in tests -- :debug generates ~95MB of output.
config.log_level = :warn
```

This is a single-line addition. The research confirmed this saves 5-15s per run by eliminating disk IO for debug/info log messages.

### Task 2: Verify integration test directory organization

Confirm all 4 integration test files are properly under `test/integration/`:
- `test/integration/host_install_flow_test.rb` (slow -- subprocess spawning)
- `test/integration/release_packaging_test.rb` (slow -- gem build)
- `test/integration/engine_mounting_test.rb` (fast -- route assertions)
- `test/integration/navigation_test.rb` (empty placeholder)

No file moves needed -- they are already in the correct location. The `--exclude-pattern` flag works with glob patterns on the file path.

### Task 3: Add Rake task for fast test runs

Create `lib/tasks/test_fast.rake` with a convenience task:

```ruby
# frozen_string_literal: true

namespace :test do
  desc "Run tests excluding slow integration tests"
  task fast: :environment do
    $stdout.puts "Running tests excluding integration/ directory..."
    system(
      "bin/rails", "test",
      "--exclude-pattern", "**/integration/**",
      exception: true
    )
  end
end
```

This provides `bin/rails test:fast` as a developer convenience that excludes the integration directory.

### Task 4: Verify both test modes work

Run verification:
```bash
# Full suite (all tests including integration)
bin/rails test

# Fast mode (excluding integration)
bin/rails test --exclude-pattern="**/integration/**"

# Lint modified files
bin/rubocop test/dummy/config/environments/test.rb lib/tasks/test_fast.rake
```

Verify the fast mode excludes the integration tests and completes significantly faster.

## Files

| Action | Path |
|--------|------|
| MODIFY | `test/dummy/config/environments/test.rb` |
| CREATE | `lib/tasks/test_fast.rake` |

## Verification

```bash
# Full suite passes
bin/rails test

# Exclude pattern works (fewer tests, no integration)
bin/rails test --exclude-pattern="**/integration/**"

# Lint
bin/rubocop test/dummy/config/environments/test.rb lib/tasks/test_fast.rake
```

## Success Criteria

- `grep "log_level" test/dummy/config/environments/test.rb` shows `:warn`
- `bin/rails test` runs all 1031+ tests (no regressions)
- `bin/rails test --exclude-pattern="**/integration/**"` runs successfully with fewer tests
- `lib/tasks/test_fast.rake` exists and is syntactically valid
