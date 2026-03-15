# Phase 01 Research: Quick Wins & Security Hardening

## Scout Findings Summary

**19 findings audited → 4 already correct → 15 actionable items**

### Already Correct (No Changes Needed)
- **V8:** MutationObserver disconnect — properly implemented with disconnect() and null cleanup
- **C8:** ItemsController defensive logging — correct defensive pattern
- **C10:** SourcesController safe_redirect_path — properly validates and sanitizes
- **V12:** Turbo Frame naming — consistent `source_monitor_[resource]_table` pattern

### Actionable Findings

#### Security & Authorization
- **C6:** ImportHistoryDismissalsController — no user ownership check on `ImportHistory.find(params[:import_history_id])`
- **C9:** DashboardController `schedule_pages_params` uses `.permit!` — needs explicit allowlist

#### Model Scopes & Methods
- **M1/M3:** ScrapeLog missing `by_source`, `by_status`, `by_item` scopes (FetchLog has `for_job`, `by_category`)
- **M5:** Source.avg_word_count hardcodes `sourcemon_item_contents` — use `ItemContent.table_name`
- **M8:** ImportSession has no state scopes — needs `in_step(step)` plus named step scopes
- **M12:** LogEntry duplicates `recent` scope already in Loggable concern — remove duplicate
- **M13:** Source.reset_items_counter! uses `update_columns` — use `update!`

#### Job Error Handling
- **S1:** ImportSessionHealthCheckJob missing `rescue_from ActiveRecord::Deadlocked` (uses `with_lock`)
- **S9:** SourceHealthCheckJob returns `result` on success, `nil` on error — confusing; jobs are fire-and-forget
- **S10:** ScheduleFetchesJob silently calls Scheduler.run with no logging

#### Controller Cleanup
- **C7:** SourceTurboResponses passes `view_context.pluralize` — use `ActionController::Base.helpers.pluralize`
- **C11:** BulkScrapeEnablementsController hardcodes `"readability"` — use `SourceMonitor.config.scraping.default_adapter`

#### View/Helper Extraction
- **V2:** Scrape status badge case/when inline in items/index.html.erb (lines 103-114) — extract to helper
- **V10:** `compact_blank` fallback pattern repeated 3x across views — extract to helper
- **V11:** Toast delay constants scattered (5000ms info, 10000ms error) — centralize

## Parallel Execution Groups

1. **Security (wave 1):** C6, C9 — independent files, highest priority
2. **Models (wave 1):** M1/M3, M5, M8, M12, M13 — independent model files
3. **Jobs (wave 1):** S1, S9, S10 — independent job files
4. **Controllers (wave 1):** C7, C11 — independent controller files
5. **Views (wave 1):** V2, V10, V11 — view helpers, may create new files

All groups can run in parallel — no cross-group file dependencies.
