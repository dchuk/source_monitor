---
phase: "02"
plan: "01"
title: "Loggable Date Scopes & Composite Indexes"
status: complete
---

## What Was Built

Added 4 reusable date range scopes (`since`, `before`, `today`, `by_date_range`) to the Loggable concern, making them available on all log models. Added 4 composite database indexes to optimize source-scoped and item-scoped date range queries on log tables.

## Commits

- `a52f484` feat(loggable): add date range scopes and composite indexes

## Tasks Completed

1. **Add date range scopes to Loggable concern** -- Added `since`, `before`, `today`, and `by_date_range` scopes to the `included` block in `Loggable`, available to all log models (FetchLog, ScrapeLog, HealthCheckLog).

2. **Create migration for composite indexes** -- Added migration `20260313120000_add_composite_indexes_to_log_tables` with 4 composite indexes: `(source_id, started_at)` on fetch_logs, scrape_logs, and health_check_logs, plus `(item_id, started_at)` on scrape_logs.

3. **Write tests for date range scopes** -- Created `test/models/concerns/source_monitor/loggable_test.rb` with 5 tests covering `since`, `before`, `today`, `by_date_range`, and chainability with existing scopes (`successful.today`).

4. **Verify composite indexes exist** -- Added index existence test asserting all 4 composite indexes are present in the schema.

## Files Modified

| Action | Path |
|--------|------|
| MODIFY | `app/models/concerns/source_monitor/loggable.rb` |
| CREATE | `db/migrate/20260313120000_add_composite_indexes_to_log_tables.rb` |
| CREATE | `test/models/concerns/source_monitor/loggable_test.rb` |

## Deviations

None. All tasks implemented as specified in the plan.
