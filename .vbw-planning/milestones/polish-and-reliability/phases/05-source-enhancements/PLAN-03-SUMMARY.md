---
phase: 5
plan: 3
title: Word Count Metrics & Display
status: complete
tasks_completed: 5
tasks_total: 5
commits:
  - hash: c1e81ac
    message: "feat(05-p3): add word count columns to item_contents"
  - hash: 506e556
    message: "feat(05-p3): add word count computation to ItemContent model"
  - hash: 5590046
    message: "feat(05-p3): display word counts in item views"
  - hash: a594f02
    message: "feat(05-p3): display avg word count on sources index"
  - hash: 479dddf
    message: "test(05-p3): add backfill rake task and comprehensive tests"
deviations:
  - "DEVN-01: Added backfill guard condition (scraped_word_count.nil? && scraped_content.present?) to compute_scraped_word_count so the rake task properly backfills records where content exists but word count was never computed"
test_results: "1158 runs, 3616 assertions, 0 failures, 0 errors, 0 skips"
rubocop: "0 offenses"
---

## What Was Built

- Migration adds scraped_word_count and feed_word_count integer columns to sourcemon_item_contents
- ItemContent before_save callback auto-computes word counts: scraped from whitespace-split scraped_content, feed from HTML-stripped item.content
- Word counts displayed on items index table, item detail Counts & Metrics section, source detail items table
- Avg word count column on sources index via single grouped SQL query (no N+1)
- Backfill rake task source_monitor:backfill_word_counts triggers save! on all existing records
- 7 new tests covering computation, display, avg_word_count, and backfill

## Files Modified

- `db/migrate/20260222194201_add_word_counts_to_item_contents.rb` — new migration
- `test/dummy/db/schema.rb` — schema update
- `app/models/source_monitor/item_content.rb` — before_save callback, total_word_count
- `app/models/source_monitor/source.rb` — avg_word_count method
- `app/controllers/source_monitor/items_controller.rb` — includes(:item_content)
- `app/controllers/source_monitor/sources_controller.rb` — avg_word_counts query, includes(:item_content)
- `app/views/source_monitor/items/index.html.erb` — Words column
- `app/views/source_monitor/items/_details.html.erb` — feed/scraped word counts
- `app/views/source_monitor/sources/_details.html.erb` — Words column in items table
- `app/views/source_monitor/sources/index.html.erb` — Avg Words column header
- `app/views/source_monitor/sources/_row.html.erb` — avg word count display
- `lib/tasks/source_monitor_tasks.rake` — backfill_word_counts task
- `test/models/source_monitor/item_content_test.rb` — word count computation tests
- `test/models/source_monitor/source_test.rb` — avg_word_count tests
- `test/controllers/source_monitor/items_controller_test.rb` — display tests
- `test/tasks/backfill_word_counts_task_test.rb` — new backfill task test
