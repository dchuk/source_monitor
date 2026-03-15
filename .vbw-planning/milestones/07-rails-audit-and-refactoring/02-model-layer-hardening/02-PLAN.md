---
phase: "02"
plan: "02"
title: "ItemContent N+1 Fix & Item Callback Guard"
wave: 1
depends_on: []
must_haves:
  - "ItemContent#compute_feed_word_count uses item.content without triggering N+1 (content is on items table, not a separate load)"
  - "Item has after_create_commit :ensure_feed_content_record callback with guard clause"
  - "ensure_feed_content_record no longer needs to be called manually from ItemCreator"
  - "Existing tests pass unchanged"
  - "New tests cover the callback behavior"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 02: ItemContent N+1 Fix & Item Callback Guard

## Objective

Fix the potential N+1 in ItemContent's `compute_feed_word_count` callback and move `ensure_feed_content_record` into an Item callback so it runs automatically on creation.

## Context

- `@app/models/source_monitor/item_content.rb` -- `compute_feed_word_count` (line 32) calls `item&.content` which triggers a lazy load of the `item` association if not already loaded
- `@app/models/source_monitor/item.rb` -- `ensure_feed_content_record` (line 38) is a public method only called from `ItemCreator`
- `item.content` is a text column on the `sourcemon_items` table -- accessing it via the `belongs_to :item` association loads the full item row if not already in memory

### N+1 Analysis

When `ItemContent` is saved independently (e.g., after scraping), `compute_feed_word_count` calls `item&.content`. If the `item` association isn't preloaded, this triggers a SELECT. This is a single extra query per save (not a classic N+1), but it's avoidable. The fix: extract to a local variable for clarity and ensure the item is loaded.

## Tasks

### Task 1: Clean up compute_feed_word_count

**Files:** `app/models/source_monitor/item_content.rb`

Change `compute_feed_word_count` (lines 32-39) to use a local variable and add a guard for when item isn't loaded:

```ruby
def compute_feed_word_count
  feed_content = item&.content
  if feed_content.blank?
    self.feed_word_count = nil
  else
    stripped = ActionView::Base.full_sanitizer.sanitize(feed_content)
    self.feed_word_count = stripped.present? ? stripped.split.size : nil
  end
end
```

This is a minor clarity improvement -- the local variable `feed_content` avoids calling `item&.content` implicitly twice (once for the blank check, once for sanitization in the original code it was only called once, but the local var makes intent clearer).

**Tests:** Existing `item_content_test.rb` tests pass unchanged
**Acceptance:** No behavioral change

### Task 2: Add after_create_commit callback to Item

**Files:** `app/models/source_monitor/item.rb`

Add after the scope declarations (around line 30):

```ruby
after_create_commit :ensure_feed_content_record, if: -> { content.present? }
```

The existing `ensure_feed_content_record` method (line 38) already has guard clauses (`return if item_content.present?`, `return if content.blank?`), making this callback safe and idempotent.

**Tests:** New tests in `test/models/source_monitor/item_test.rb`
**Acceptance:** Creating an item with content automatically creates an ItemContent record

### Task 3: Remove manual ensure_feed_content_record call from ItemCreator

**Files:** Search with `grep -r ensure_feed_content_record lib/` to find call sites

Remove the manual call to `ensure_feed_content_record` from wherever it's called in the fetching/item creation pipeline. The callback now handles it.

Keep the public method on Item -- it's useful for backfill operations and is idempotent.

**Tests:** Existing `entry_parser_test.rb` / `item_creator_test.rb` tests pass unchanged
**Acceptance:** No manual calls to `ensure_feed_content_record` after item creation in lib code

### Task 4: Write tests for callback behavior

**Files:** `test/models/source_monitor/item_test.rb`

Add tests in a new section "ensure_feed_content_record callback":

1. `test "creating item with content auto-creates ItemContent"` -- create item with content via `create!`, assert `item.reload.item_content` present and `feed_word_count` is computed
2. `test "creating item without content does not create ItemContent"` -- create item with blank content, assert `item.reload.item_content` nil
3. `test "ensure_feed_content_record is idempotent"` -- create item with content (callback fires), call `ensure_feed_content_record` again, assert still only one ItemContent record

Use `create_source!` factory. Note: `after_create_commit` fires after the transaction commits, so use `item.reload` to check results.

**Acceptance:** All 3 tests pass

## Files

| Action | Path |
|--------|------|
| MODIFY | `app/models/source_monitor/item_content.rb` |
| MODIFY | `app/models/source_monitor/item.rb` |
| MODIFY | `lib/source_monitor/fetching/item_creator/entry_parser.rb` (if call exists) |
| MODIFY | `test/models/source_monitor/item_test.rb` |

## Verification

```bash
bin/rails test test/models/source_monitor/item_test.rb test/models/source_monitor/item_content_test.rb
bin/rails test test/lib/source_monitor/fetching/
bin/rubocop app/models/source_monitor/item.rb app/models/source_monitor/item_content.rb
```

## Success Criteria

- Items with content auto-create ItemContent records on creation
- No manual `ensure_feed_content_record` calls needed after item creation
- compute_feed_word_count uses local variable for clarity
- All existing + new tests pass
- Zero RuboCop offenses
