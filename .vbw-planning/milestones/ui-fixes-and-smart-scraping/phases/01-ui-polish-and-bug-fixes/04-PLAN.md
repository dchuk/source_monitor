---
phase: "01"
plan: "04"
title: "Sortable Computed Columns on Sources Index"
wave: 1
depends_on: []
must_haves:
  - "New Items/Day column sortable via Ransack"
  - "Avg Feed Words column sortable via Ransack"
  - "Avg Scraped Words column sortable via Ransack"
  - "Match existing sort pattern (table_sort_link, arrows, aria)"
---

## Tasks

### Task 1: Add ransackers to Source model

Define three `ransacker` blocks on the Source model for the computed columns.

**Files:**
- Modify: `app/models/source_monitor/source.rb` — add ransacker definitions

**Details:**
- `ransacker :new_items_per_day` — subquery counting items created in last 30 days divided by 30
- `ransacker :avg_feed_words` — subquery averaging feed_word_count from item_contents
- `ransacker :avg_scraped_words` — subquery averaging scraped_word_count from item_contents
- Each ransacker returns an Arel node that PostgreSQL can sort by
- Example pattern:
  ```ruby
  ransacker :avg_feed_words do
    Arel.sql("(SELECT AVG(ic.feed_word_count) FROM #{ItemContent.table_name} ic INNER JOIN #{Item.table_name} i ON i.id = ic.item_id WHERE i.source_id = #{table_name}.id AND ic.feed_word_count IS NOT NULL)")
  end
  ```

### Task 2: Update sources index view for sortable headers

Replace the plain `<th>` headers for the three columns with the `table_sort_link` pattern.

**Files:**
- Modify: `app/views/source_monitor/sources/index.html.erb` — lines 171-173

**Details:**
- Replace each plain `<th>` with the same structure used by Items/Last Fetch columns:
  ```erb
  <th scope="col" class="px-6 py-3" data-sort-column="avg_feed_words" aria-sort="<%= table_sort_aria(@q, :avg_feed_words) %>">
    <span class="inline-flex items-center gap-1">
      <%= table_sort_link(@q, :avg_feed_words, "Avg Feed Words", frame: "source_monitor_sources_table", default_order: :desc, secondary: ["created_at desc"], html_options: { class: "inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-wide text-slate-600 hover:text-slate-900 focus:outline-none" }) %>
      <span class="text-[11px] text-slate-400" aria-hidden="true"><%= table_sort_arrow(@q, :avg_feed_words) %></span>
    </span>
  </th>
  ```
- Apply same pattern for `new_items_per_day` and `avg_scraped_words`
- Default sort order: desc for all three (higher values first)

### Task 3: Test sortable columns

Write integration tests verifying the sort links work.

**Files:**
- Create: `test/controllers/source_monitor/sources_controller_sort_test.rb`

**Acceptance:**
- GET /sources?q[s]=avg_feed_words+desc returns sources sorted by average feed word count
- GET /sources?q[s]=avg_scraped_words+asc returns sources in ascending order
- GET /sources?q[s]=new_items_per_day+desc returns sources sorted by activity rate
- Sort arrows reflect current sort direction
- Columns that have no data sort without errors (NULL handling)
