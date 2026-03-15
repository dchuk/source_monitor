---
phase: "04"
plan: "03"
title: "Result Pattern for Completion Handlers & Consistent Logging"
wave: 1
depends_on: []
skills_used:
  - sm-pipeline-stage
  - sm-architecture
  - tdd-cycle
must_haves:
  - "RetentionHandler returns Result struct with status (:applied/:skipped/:failed), removed_total, and error fields"
  - "FollowUpHandler returns Result struct with status (:applied/:skipped/:failed), enqueued_count, errors fields"
  - "EventPublisher returns Result struct with status (:published/:skipped/:failed) and error field"
  - "FetchRunner logs warnings when completion handler results indicate failure"
  - "Scheduler (fetch) has rescue StandardError with warn-level logging"
  - "Scheduler (scrape) has rescue StandardError with warn-level logging"
  - "RetentionHandler log prefix includes full class name [SourceMonitor::Fetching::Completion::RetentionHandler]"
  - "FollowUpHandler log prefix uses consistent format [SourceMonitor::Fetching::Completion::FollowUpHandler]"
  - "Tests for each handler verify Result struct on success and failure paths"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 03: Result Pattern for Completion Handlers & Consistent Logging

## Objective

Add Result pattern to EventPublisher, RetentionHandler, and FollowUpHandler (S4), standardize their log formats (S5), add error handling to fetch/scrape Schedulers, and wire Result usage into FetchRunner for visibility.

## Context

- @.claude/skills/sm-pipeline-stage/SKILL.md -- Pipeline architecture, completion handler patterns
- @.claude/skills/sm-architecture/SKILL.md -- Module structure, Result pattern usage across codebase
- @.claude/skills/tdd-cycle/SKILL.md -- TDD workflow
- RetentionHandler (30 lines) catches StandardError, logs with generic prefix, returns nil
- FollowUpHandler (43 lines) has per-item rescue, inconsistent log format, returns nil
- EventPublisher (20 lines) has no error handling at all, returns nil
- FetchRunner calls all three but ignores return values -- cannot detect handler failures
- Existing Result patterns: ItemCreator::Result, Enqueuer::Result, ItemScraper::Result, FeedFetcher::Result
- Fetch Scheduler (86 lines) and Scrape Scheduler (41 lines) have no error handling

## Tasks

### Task 1: Write handler Result tests (TDD red)

Create/update test files:
- `test/lib/source_monitor/fetching/completion/retention_handler_test.rb`: test returns Result with :applied on success; test returns Result with :failed and error on StandardError; test :skipped when result status is not :fetched
- `test/lib/source_monitor/fetching/completion/follow_up_handler_test.rb`: test returns Result with :applied and enqueued_count; test returns Result with :failed on error; test per-item errors captured in errors array
- `test/lib/source_monitor/fetching/completion/event_publisher_test.rb`: test returns Result with :published on success; test returns Result with :failed on error

### Task 2: Add Result structs to completion handlers

Modify three files:
- `lib/source_monitor/fetching/completion/retention_handler.rb`: Add `Result = Struct.new(:status, :removed_total, :error, keyword_init: true)` with `success?` helper. Return Result from `call`.
- `lib/source_monitor/fetching/completion/follow_up_handler.rb`: Add `Result = Struct.new(:status, :enqueued_count, :errors, keyword_init: true)` with `success?` helper. Return Result from `call`. Collect per-item errors into `errors` array.
- `lib/source_monitor/fetching/completion/event_publisher.rb`: Add `Result = Struct.new(:status, :error, keyword_init: true)` with `success?` helper. Wrap dispatch in begin/rescue, return Result.

### Task 3: Standardize logging in handlers and schedulers

Modify completion handlers (same files as Task 2):
- RetentionHandler: change log prefix from `[SourceMonitor]` to `[SourceMonitor::Fetching::Completion::RetentionHandler]`
- FollowUpHandler: change log prefix to `[SourceMonitor::Fetching::Completion::FollowUpHandler]` (consistent format)

Modify schedulers:
- `lib/source_monitor/scheduler.rb` (fetch): wrap `run` body in begin/rescue StandardError, log at warn level with `[SourceMonitor::Scheduler]` prefix
- `lib/source_monitor/scraping/scheduler.rb` (scrape): wrap `run` body in begin/rescue StandardError, log at warn level with `[SourceMonitor::Scraping::Scheduler]` prefix

### Task 4: Wire Result usage in FetchRunner

Modify `lib/source_monitor/fetching/fetch_runner.rb`:
- Capture return values from `retention_handler.call`, `follow_up_handler.call`, `event_publisher.call`
- Log at warn level when any handler returns a non-success Result
- No behavioral change -- FetchRunner continues execution regardless (handlers are best-effort)

### Task 5: Verify

- `bin/rails test test/lib/source_monitor/fetching/completion/` -- all completion handler tests pass
- `bin/rails test test/lib/source_monitor/fetching/fetch_runner_test.rb` -- FetchRunner tests pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
- Verify consistent log format: `grep -r "\[SourceMonitor::" lib/source_monitor/fetching/completion/` shows uniform prefixes
