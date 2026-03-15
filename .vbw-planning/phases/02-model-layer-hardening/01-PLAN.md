---
phase: "02"
plan: "01"
title: "Loggable Date Scopes & Composite Indexes"
wave: 1
depends_on: []
must_haves:
  - "Loggable concern has since(date), before(date), today, and by_date_range(start, finish) scopes"
  - "All 3 log models (FetchLog, ScrapeLog, HealthCheckLog) inherit date scopes via Loggable"
  - "Migration adds 4 composite indexes: (source_id, started_at) on fetch_logs, scrape_logs, health_check_logs + (item_id, started_at) on scrape_logs"
  - "Tests cover all 4 date scopes on at least one log model"
  - "Tests verify composite indexes exist in schema"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 01: Loggable Date Scopes & Composite Indexes

## Objective

Add reusable date range scopes to the Loggable concern so all log models can efficiently filter by date, and add composite indexes to support those queries and common source-scoped log lookups.

## Context

- `@app/models/concerns/source_monitor/loggable.rb` -- shared concern for FetchLog, ScrapeLog, HealthCheckLog
- Already has `recent`, `successful`, `failed` scopes on `started_at`
- Schema has single-column indexes on `source_id` and `started_at` for each log table, but no composite indexes
- Common query pattern: "fetch logs for source X in the last 7 days" needs (source_id, started_at) composite index

## Tasks

### Task 1: Add date range scopes to Loggable concern

**Files:** `app/models/concerns/source_monitor/loggable.rb`

Add these scopes inside the `included` block, after the existing scopes:

```ruby
scope :since, ->(date) { where(arel_table[:started_at].gteq(date)) }
scope :before, ->(date) { where(arel_table[:started_at].lteq(date)) }
scope :today, -> { since(Time.current.beginning_of_day) }
scope :by_date_range, ->(start_date, end_date) { since(start_date).before(end_date) }
```

**Tests:** `test/models/concerns/source_monitor/loggable_test.rb` (new file)
**Acceptance:** Scopes return correct records when chained; `FetchLog.today` returns only today's logs

### Task 2: Create migration for composite indexes

**Files:** New migration file

Create migration `AddCompositeIndexesToLogTables`:

```ruby
add_index :sourcemon_fetch_logs, [:source_id, :started_at],
          name: "index_fetch_logs_on_source_id_and_started_at"
add_index :sourcemon_scrape_logs, [:source_id, :started_at],
          name: "index_scrape_logs_on_source_id_and_started_at"
add_index :sourcemon_scrape_logs, [:item_id, :started_at],
          name: "index_scrape_logs_on_item_id_and_started_at"
add_index :sourcemon_health_check_logs, [:source_id, :started_at],
          name: "index_health_check_logs_on_source_id_and_started_at"
```

**Tests:** Assert indexes exist in schema test or migration test
**Acceptance:** `bin/rails db:migrate` succeeds; schema.rb shows 4 new composite indexes

### Task 3: Write tests for date range scopes

**Files:** `test/models/concerns/source_monitor/loggable_test.rb` (new file)

Test using FetchLog as the concrete model (all 3 log models share the concern):

1. `test "since scope returns logs on or after date"` -- create logs at different times, verify filtering
2. `test "before scope returns logs on or before date"` -- same pattern
3. `test "today scope returns only today's logs"` -- create yesterday + today logs
4. `test "by_date_range scope returns logs within range"` -- create 3 logs, verify middle one included
5. `test "date scopes are chainable with existing scopes"` -- `FetchLog.successful.today` returns correct subset

Use `create_source!` factory + direct FetchLog creation with explicit `started_at` values.

**Acceptance:** All 5 tests pass

### Task 4: Verify composite indexes exist

**Files:** `test/models/concerns/source_monitor/loggable_test.rb` (append to same file)

Add test that verifies indexes exist on each table:

```ruby
test "composite indexes exist on log tables" do
  assert ActiveRecord::Base.connection.index_exists?(:sourcemon_fetch_logs, [:source_id, :started_at])
  assert ActiveRecord::Base.connection.index_exists?(:sourcemon_scrape_logs, [:source_id, :started_at])
  assert ActiveRecord::Base.connection.index_exists?(:sourcemon_scrape_logs, [:item_id, :started_at])
  assert ActiveRecord::Base.connection.index_exists?(:sourcemon_health_check_logs, [:source_id, :started_at])
end
```

**Acceptance:** Test passes confirming all 4 indexes exist

## Files

| Action | Path |
|--------|------|
| MODIFY | `app/models/concerns/source_monitor/loggable.rb` |
| CREATE | `db/migrate/YYYYMMDDHHMMSS_add_composite_indexes_to_log_tables.rb` |
| CREATE | `test/models/concerns/source_monitor/loggable_test.rb` |

## Verification

```bash
bin/rails db:migrate
bin/rails test test/models/concerns/source_monitor/loggable_test.rb
bin/rubocop app/models/concerns/source_monitor/loggable.rb
```

## Success Criteria

- 4 date scopes available on all log models via Loggable concern
- 4 composite indexes added to log tables
- All new tests pass
- Zero RuboCop offenses
