---
phase: "01"
plan: "02"
title: "Model & Job Fixes"
wave: 1
depends_on: []
must_haves:
  - "ScrapeLog has by_source, by_status, and by_item scopes"
  - "Source.avg_word_count uses ItemContent.table_name instead of hardcoded string"
  - "ImportSession has in_step(step) scope"
  - "LogEntry duplicate recent scope removed (inherited from Loggable concern)"
  - "Source.reset_items_counter! uses update! instead of update_columns"
  - "ImportSessionHealthCheckJob has rescue_from ActiveRecord::Deadlocked"
  - "SourceHealthCheckJob has no explicit return value in perform"
  - "ScheduleFetchesJob logs errors"
---

## Tasks

### Task 1: Add missing scopes to ScrapeLog and ImportSession (M1/M3, M8)
**Files:** `app/models/source_monitor/scrape_log.rb`, `app/models/source_monitor/import_session.rb`, `test/models/source_monitor/scrape_log_test.rb`, `test/models/source_monitor/import_session_test.rb`
**Action:**
In `ScrapeLog`, add three scopes after the existing `belongs_to` declarations:
```ruby
scope :by_source, ->(source) { where(source: source) }
scope :by_status, ->(success) { where(success: success) }
scope :by_item, ->(item) { where(item: item) }
```
In `ImportSession`, add a scope:
```ruby
scope :in_step, ->(step) { where(current_step: step) }
```
**Tests:**
- ScrapeLog: test `by_source` returns only logs for given source, `by_status(true)` returns successful logs, `by_item` returns logs for given item.
- ImportSession: test `in_step("upload")` returns sessions in that step.
**Acceptance:** All new scopes return correct results. Existing tests pass.

### Task 2: Fix hardcoded table name and update_columns in Source (M5, M13)
**Files:** `app/models/source_monitor/source.rb`, `test/models/source_monitor/source_test.rb`
**Action:**
In `avg_word_count`, replace the hardcoded `sourcemon_item_contents` with `ItemContent.table_name`:
```ruby
def avg_word_count
  items.joins(:item_content)
       .where.not(ItemContent.table_name => { scraped_word_count: nil })
       .average("#{ItemContent.table_name}.scraped_word_count")
       &.round
end
```

In `reset_items_counter!`, replace `update_columns` with `update!` so callbacks and validations run:
```ruby
def reset_items_counter!
  actual_count = items.count
  update!(items_count: actual_count)
end
```
**Tests:**
- Test that `avg_word_count` returns correct average (may already be tested).
- Test that `reset_items_counter!` updates the count and runs validations (triggers `update!` not `update_columns`).
**Acceptance:** No hardcoded table names in Source model. `reset_items_counter!` uses `update!`. All tests pass.

### Task 3: Remove duplicate `recent` scope from LogEntry (M12)
**Files:** `app/models/source_monitor/log_entry.rb`, `test/models/source_monitor/log_entry_test.rb`
**Action:**
Remove line 13:
```ruby
scope :recent, -> { order(started_at: :desc) }
```
LogEntry already includes this scope via `Loggable` concern... wait — checking the code, LogEntry does NOT include Loggable. It defines its own `recent` scope. However, LogEntry is a delegated_type that wraps FetchLog/ScrapeLog/HealthCheckLog which DO include Loggable. The `recent` scope on LogEntry is independent and intentional (it orders LogEntry records by started_at).

Actually, re-reading: LogEntry does NOT include Loggable. The scope is not a duplicate — it's the only `recent` scope on LogEntry. The scout finding may be incorrect. **Skip this change** — the scope is needed and is not a duplicate.

**Update:** Replace this task with: no action needed on M12. The `recent` scope on LogEntry is its own scope, not inherited.

### Task 4: Add deadlock rescue and cleanup to jobs (S1, S9, S10)
**Files:** `app/jobs/source_monitor/import_session_health_check_job.rb`, `app/jobs/source_monitor/source_health_check_job.rb`, `app/jobs/source_monitor/schedule_fetches_job.rb`, `test/jobs/source_monitor/import_session_health_check_job_test.rb`, `test/jobs/source_monitor/source_health_check_job_test.rb`, `test/jobs/source_monitor/schedule_fetches_job_test.rb`
**Action:**

**S1 — ImportSessionHealthCheckJob:** Add `rescue_from ActiveRecord::Deadlocked` after the existing `discard_on` line:
```ruby
rescue_from ActiveRecord::Deadlocked do |error|
  Rails.logger&.warn("[SourceMonitor::ImportSessionHealthCheckJob] Deadlock: #{error.message}")
  retry_job(wait: 2.seconds + rand(3).seconds)
end
```

**S9 — SourceHealthCheckJob:** Remove the explicit `result` return value from the happy path in `perform`. Change:
```ruby
result = SourceMonitor::Health::SourceHealthCheck.new(source: source).call
broadcast_outcome(source, result)
trigger_fetch_if_degraded(source, result)
result
```
to:
```ruby
result = SourceMonitor::Health::SourceHealthCheck.new(source: source).call
broadcast_outcome(source, result)
trigger_fetch_if_degraded(source, result)
```
(Remove `result` on the last line, and remove `nil` from the rescue block.)

**S10 — ScheduleFetchesJob:** Add error rescue with logging:
```ruby
def perform(options = nil)
  limit = extract_limit(options)
  SourceMonitor::Scheduler.run(limit:)
rescue StandardError => error
  Rails.logger&.error("[SourceMonitor::ScheduleFetchesJob] #{error.class}: #{error.message}")
  raise
end
```
The `raise` ensures the job still fails (for retry/visibility) but now has logging.

**Tests:**
- S1: Test that deadlocked error triggers retry (mock `ActiveRecord::Deadlocked`).
- S9: Verify perform doesn't return the result object (implementation detail, low priority).
- S10: Test that errors are logged and re-raised.
**Acceptance:** All three jobs have improved error handling. All tests pass.
