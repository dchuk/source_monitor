---
phase: 4
plan: 3
title: Published Column Fix
wave: 1
depends_on: []
must_haves:
  - Published column shows actual dates instead of "Unpublished" for all items
  - Root cause identified and fixed
---

# Plan 3: Published Column Fix

Investigate why the published column shows "Unpublished" for every item and fix the root cause.

## Tasks

### Task 1: Investigate published_at population

**Files:** `lib/source_monitor/items/item_creator/entry_parser.rb`, `lib/source_monitor/items/item_creator.rb`

1. Check `extract_timestamp` method -- it looks for `published` then `updated` on Feedjira entries
2. Trace how the parsed `published_at` value flows from EntryParser through ItemCreator to the database
3. Check if `published_at` is in the permitted/assigned attributes during item creation
4. Check if there's an `attr_accessible` or strong params filter that strips it
5. Look at the actual database data: run `SourceMonitor::Item.where.not(published_at: nil).count` vs `SourceMonitor::Item.count`

The entry_parser.rb correctly extracts timestamp (line 30: `published_at = extract_timestamp`), and includes it in the returned hash (line 47: `published_at: published_at`). So the parser side looks correct. The issue is likely in how ItemCreator uses this hash to create/update the Item record.

### Task 2: Fix the root cause

Based on investigation:
- If `published_at` is being filtered out during item creation, add it to permitted attributes
- If Feedjira doesn't expose `published` for certain feed types, add the missing method mapping
- If the field is populated but nil for specific feed formats, add fallback extraction logic

### Task 3: Add created_at fallback for display

**Files:** `app/views/source_monitor/items/index.html.erb` (line 94), `app/views/source_monitor/items/_details.html.erb`, `app/views/source_monitor/sources/_details.html.erb`

Regardless of parser fix, add a display fallback. If `published_at` is nil, show `created_at` with a subtle visual indicator:

```erb
<% if item.published_at %>
  <%= item.published_at.strftime("%b %d, %Y %H:%M") %>
<% else %>
  <span class="text-slate-400"><%= item.created_at.strftime("%b %d, %Y %H:%M") %></span>
<% end %>
```

Update all three views that display published_at.

### Task 4: Add tests

- Test that items created from feeds with pubDate have published_at set
- Test display fallback when published_at is nil
- Verify existing item tests still pass

## Acceptance Criteria

- [ ] Root cause of nil published_at identified and documented
- [ ] Items from feeds with published dates have published_at populated
- [ ] Items without published dates show created_at with visual distinction
- [ ] All views showing published_at use the fallback pattern
- [ ] All existing tests pass plus new tests
- [ ] RuboCop zero offenses
