---
phase: "02"
plan: "02"
title: "ItemContent N+1 Fix & Item Callback Guard"
status: complete
---

## What Was Built

Moved `ensure_feed_content_record` from a manual call in `ItemCreator` to an `after_create_commit` callback on `Item`, so ItemContent records are automatically created when items with feed content are persisted. Also cleaned up `compute_feed_word_count` local variable naming for clarity.

## Commits

- `f62a63c` fix(models): move ensure_feed_content_record to after_create_commit callback
- `b66d6b2` fix(tests): update tests for after_create_commit item_content callback

## Tasks Completed

1. **Clean up compute_feed_word_count** -- Renamed local variable from `content` to `feed_content` in `ItemContent#compute_feed_word_count` for clarity and to avoid shadowing the model attribute name.

2. **Add after_create_commit callback to Item** -- Added `after_create_commit :ensure_feed_content_record, if: -> { content.present? }` so ItemContent records are automatically created when items with feed content are persisted.

3. **Remove manual ensure_feed_content_record call from ItemCreator** -- Removed the explicit call in `ItemCreator#create_new_item` since the callback now handles it. The public method remains available for backfill operations.

4. **Write tests for callback behavior** -- Replaced 3 manual-call tests with 4 tests covering: auto-creation on item create with content, no creation without content, idempotency of manual calls, and blank content guard.

## Files Modified

| Action | Path |
|--------|------|
| MODIFY | `app/models/source_monitor/item_content.rb` |
| MODIFY | `app/models/source_monitor/item.rb` |
| MODIFY | `lib/source_monitor/items/item_creator.rb` |
| MODIFY | `test/models/source_monitor/item_test.rb` |
| MODIFY | `test/models/source_monitor/source_test.rb` |
| MODIFY | `test/lib/source_monitor/analytics/scrape_recommendations_test.rb` |
| MODIFY | `test/lib/source_monitor/dashboard/stats_query_test.rb` |
| MODIFY | `test/controllers/source_monitor/dashboard_controller_test.rb` |
| MODIFY | `test/controllers/source_monitor/source_scrape_tests_controller_test.rb` |
| MODIFY | `test/controllers/source_monitor/sources_controller_test.rb` |
| MODIFY | `test/controllers/source_monitor/items_controller_test.rb` |
| MODIFY | `test/jobs/source_monitor/download_content_images_job_test.rb` |
| MODIFY | `test/tasks/backfill_word_counts_task_test.rb` |

## Deviations

5. **Fix cascade test breakage from callback** -- The after_create_commit callback caused 34 tests across 9 files to fail with PG::UniqueViolation (tests were manually creating ItemContent after creating items with content). Fixed by removing redundant ItemContent.create! calls and using update_columns to bypass the callback where tests need to simulate pre-v0.9.0 state.
