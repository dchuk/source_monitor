---
phase: 5
plan: 3
title: Word Count Metrics & Display
wave: 2
depends_on: [1]
must_haves:
  - "migration adds scraped_word_count and feed_word_count integer columns to sourcemon_item_contents"
  - "ItemContent before_save callback computes word counts: scraped from scraped_content (split on whitespace), feed from item.content (strip HTML then split)"
  - "word counts displayed on items index table, source detail items table, item detail page"
  - "avg word count column displayed on sources index _row partial"
  - "rake task source_monitor:backfill_word_counts populates existing records"
  - "all existing tests pass, new tests cover word count computation and display"
  - "RuboCop zero offenses"
skills_used:
  - sm-engine-migration
---

## Objective

Add word count tracking to item_contents (scraped_word_count and feed_word_count), display word counts across all item-related views, and add an average word count column to the sources index. Include a backfill rake task for existing records.

## Context

- `@` `app/models/source_monitor/item_content.rb` -- current model: belongs_to :item, has scraped_content and scraped_html columns
- `@` `app/models/source_monitor/item.rb` -- delegates scraped_html/scraped_content to item_content; has content column for feed content
- `@` `app/views/source_monitor/items/index.html.erb` -- items table: title, source, published, scrape status columns
- `@` `app/views/source_monitor/items/_details.html.erb` -- item detail page with "Counts & Metrics" section
- `@` `app/views/source_monitor/sources/_details.html.erb` -- source detail items table: title, categories, tags, published, scrape status
- `@` `app/views/source_monitor/sources/_row.html.erb` -- source row in sources index: name, status, fetch interval, items, new items/day, last fetch
- `@` `app/views/source_monitor/sources/index.html.erb` -- sources index table headers (Plan 1 adds pagination here; this plan adds avg words column)
- `@` `lib/source_monitor/scraping/item_scraper/persistence.rb` -- where scraped_content is assigned to item (triggers item_content creation)
- `@` `.claude/skills/sm-engine-migration/SKILL.md` -- migration conventions

**Note:** This plan depends on Plan 1 (wave 2) because both modify `sources/index.html.erb` and `sources/_row.html.erb`. Plan 1 adds pagination controls and filter dropdowns; this plan adds an "Avg Words" column header and cell.

## Tasks

### Task 1: Add word count columns via migration

**Files:** `db/migrate/TIMESTAMP_add_word_counts_to_item_contents.rb`

Create migration adding `scraped_word_count` (integer, default: nil) and `feed_word_count` (integer, default: nil) to `sourcemon_item_contents`. No index needed -- these are display-only values, not query filters.

### Task 2: Add word count computation to ItemContent model

**Files:** `app/models/source_monitor/item_content.rb`

Add `before_save :compute_word_counts` callback. In the callback:
- `scraped_word_count`: if `scraped_content_changed?` and `scraped_content.present?`, set to `scraped_content.split.size`; if scraped_content blank, set to nil
- `feed_word_count`: if item's `content` column changed or on first save, strip HTML tags from `item.content` using `ActionView::Base.full_sanitizer.sanitize(item.content)` then split and count; if blank, set to nil

Add convenience method `total_word_count` returning `[scraped_word_count, feed_word_count].compact.max || 0` for display.

Add `Source#avg_word_count` method that queries: `items.joins(:item_content).where.not(item_contents: { scraped_word_count: nil }).average('sourcemon_item_contents.scraped_word_count')&.round`.

### Task 3: Display word counts in item views

**Files:** `app/views/source_monitor/items/index.html.erb`, `app/views/source_monitor/items/_details.html.erb`, `app/views/source_monitor/sources/_details.html.erb`

**Items index:** Add "Words" column header after "Scrape Status". In each row, display `item.item_content&.scraped_word_count || "—"`. Add `includes(:item_content)` to the controller query if not already present (check ItemsController scope).

**Item detail:** In the "Counts & Metrics" section, add "Feed Word Count" and "Scraped Word Count" rows displaying the values from item_content (or "—" if nil).

**Source detail items table:** Add "Words" column header after "Scrape Status". Display `item.item_content&.scraped_word_count || "—"` per row. Add `.includes(:item_content)` to the items query in the view or controller.

### Task 4: Display avg word count on sources index

**Files:** `app/views/source_monitor/sources/index.html.erb`, `app/views/source_monitor/sources/_row.html.erb`, `app/controllers/source_monitor/sources_controller.rb`

Add "Avg Words" column header in `index.html.erb` table header row (after "New Items / Day", before "Last Fetch"). In `_row.html.erb`, display the avg word count for the source.

For performance, compute avg word counts in a single query in the controller: `@avg_word_counts = SourceMonitor::ItemContent.joins(:item).where(items: { source_id: @sources.map(&:id) }).where.not(scraped_word_count: nil).group('sourcemon_items.source_id').average(:scraped_word_count)`. Pass as local to the row partial. Display `avg_word_counts[source.id]&.round || "—"`.

### Task 5: Backfill rake task and tests

**Files:** `lib/tasks/source_monitor_tasks.rake`, `test/models/source_monitor/item_content_test.rb`, `test/controllers/source_monitor/items_controller_test.rb`

**Rake task:** Add `source_monitor:backfill_word_counts` that iterates `ItemContent.find_each` and calls `save!` to trigger the before_save callback. Print progress every 100 records.

**Tests:** (1) ItemContent computes scraped_word_count on save when scraped_content present, (2) computes feed_word_count stripping HTML from item.content, (3) sets to nil when content is blank, (4) Source#avg_word_count returns correct average, (5) backfill rake task populates word counts for existing records. (6) Items index renders word count column, (7) Item detail shows word counts in metrics section.

Run full test suite to verify no regressions.

## Verification

```bash
bin/rails test test/models/source_monitor/item_content_test.rb test/controllers/source_monitor/items_controller_test.rb
bin/rails test
bin/rubocop app/models/source_monitor/item_content.rb app/models/source_monitor/item.rb lib/tasks/source_monitor_tasks.rake
```

## Success Criteria

- item_contents has scraped_word_count and feed_word_count columns
- Word counts computed automatically on ItemContent save
- Scraped word count: split on whitespace from scraped_content (already cleaned by readability)
- Feed word count: strip HTML from item.content then split on whitespace
- Word counts displayed on items index, source detail items table, item detail
- Avg word count displayed on sources index per source
- Backfill rake task populates existing records
- All tests pass, RuboCop zero offenses
