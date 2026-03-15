# Phase 02 Research: Model Layer Hardening

## Scout Findings Summary

7 findings researched. Key risks identified around enum conversion (DB constraints, widespread string comparisons) and state-as-records (new table/model).

### Low Risk (Scopes & Indexes)
- **M6**: No date range scopes on any log models. Loggable concern has `recent`, `successful`, `failed` only. Add `since`, `until`, `today`, `by_date_range` to Loggable.
- **M14**: Missing composite indexes on log tables: (source_id, started_at) on FetchLog/ScrapeLog/HealthCheckLog, (item_id, started_at) on ScrapeLog. 4 indexes to add.

### Medium Risk (N+1 & Callback)
- **M4**: ItemContent `compute_feed_word_count` calls `item&.content` in before_save — N+1 risk. Should pass content directly or preload.
- **M9**: `Item.ensure_feed_content_record` only called from ItemCreator, not callbacks. Add `after_create_commit` with guard.

### High Risk (Enum Conversion)
- **M10/M11**: fetch_status uses FETCH_STATUS_VALUES constant + validation. health_status uses 6 values (working, healthy, unhealthy, declining, improving, failing). DB has CHECK constraint on fetch_status. 15+ string comparisons throughout codebase. Enum conversion requires: migration, constraint update, all string comparisons updated.

### High Risk (State-as-Records)
- **M2**: soft_delete! manually decrements counter with `decrement_counter`. Would need new ItemStateChange table/model.
- **M7**: scrape_candidates uses raw SQL subquery — extract to Query Object following StatsQuery pattern.

## Parallel Execution Groups
- Group A: M6 + M14 (scopes + indexes, independent)
- Group B: M10/M11 (enum conversion, touches Source + Item + many consumers)
- Group C: M4 + M9 (ItemContent/Item callback fixes)
- Group D: M7 + M2 (query object + state-as-records refactoring)
