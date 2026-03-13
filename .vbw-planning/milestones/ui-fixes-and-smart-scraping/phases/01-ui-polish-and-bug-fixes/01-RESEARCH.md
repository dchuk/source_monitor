# Phase 01: UI Polish & Bug Fixes -- Research

## Findings

### 1. OPML Import Banner

**Key files:**
- `app/models/source_monitor/import_history.rb` — model with `user_id`, `imported_sources`, `failed_sources`, `skipped_duplicates`, `started_at`, `completed_at`
- `app/views/source_monitor/sources/_import_history_panel.html.erb` — renders banner on sources index showing latest import stats
- `app/controllers/source_monitor/sources_controller.rb:45` — loads `@recent_import_histories` via `ImportHistory.recent_for(user_id).limit(5)`
- `db/migrate/20251125094500_create_import_histories.rb` — schema: user_id, jsonb columns, timestamps. **No `dismissed_at` column yet.**
- `config/routes.rb` — no dedicated route for import_histories dismissal

**Current behavior:** Banner always shows the latest import. No dismiss mechanism exists. The panel is rendered inside `sources/index.html.erb` line 44.

**What's needed:** Migration to add `dismissed_at` to import_histories, a route/endpoint to PATCH dismiss, Turbo Stream to remove the panel element `#source_monitor_import_history_panel`.

### 2. SVG Favicon Handling

**Key files:**
- `lib/source_monitor/favicons/discoverer.rb` — downloads favicons, checks `allowed_content_types`
- `lib/source_monitor/configuration/favicons_settings.rb` — `DEFAULT_ALLOWED_CONTENT_TYPES` includes `image/svg+xml`
- `app/helpers/source_monitor/application_helper.rb:242-323` — `source_favicon_tag` renders favicon or placeholder
- `app/helpers/source_monitor/application_helper.rb:297-308` — `favicon_image_tag` uses `rails_blob_path` directly (no variant processing)
- `app/jobs/source_monitor/favicon_fetch_job.rb` — async favicon fetching
- `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` — triggers favicon fetch during feed processing

**Current behavior:** SVG favicons are downloaded and stored as-is via Active Storage. They're rendered as `<img>` tags. SVGs may not render correctly as small favicons and pose XSS risk if rendered inline.

**What's needed:** After downloading, detect SVG content type and convert to PNG using MiniMagick before attaching to Active Storage. The `Discoverer` or a post-processing step should handle conversion.

### 3. Recent Activity Heading

**Key files:**
- `app/views/source_monitor/dashboard/_recent_activity.html.erb` — renders event list
- `lib/source_monitor/dashboard/recent_activity_presenter.rb` — builds view models for events

**Current heading structure (fetch events):**
- Line 14: `event[:label]` = `"Fetch #2210"` (linked, bold)
- Line 19: Badge showing `event[:type].to_s.humanize` = `"Fetch"`
- Line 22: `event[:description]` = `"3 created / 0 updated"`
- Line 24-31: `event[:url_display]` shown below as small gray text (domain only)

**Presenter fetch_event (line 32-43):**
- `label: "Fetch ##{event.id}"`
- `url_display: domain` (extracted from feed_url)
- `url_href: event.source_feed_url`

**What's needed per decision:** URL should lead the heading row: "fhur.me -- Fetch #2210 FETCH". Source name line removed. Change the presenter to put domain in label, or restructure the view to lead with URL.

### 4. Sortable Columns on Sources Index

**Key files:**
- `app/views/source_monitor/sources/index.html.erb:110-194` — table with sortable Name, Fetch Interval, Items, Last Fetch columns
- `app/helpers/source_monitor/table_sort_helper.rb` — `table_sort_link`, `table_sort_arrow`, `table_sort_aria` helpers
- `app/controllers/concerns/source_monitor/sanitizes_search_params.rb` — `searchable_with`, `build_search_query` using Ransack
- `app/controllers/source_monitor/sources_controller.rb:12` — `searchable_with scope: -> { Source.all }, default_sorts: ["created_at desc"]`

**Existing sort pattern (e.g., Items column, lines 152-170):**
```erb
<th scope="col" class="px-6 py-3" data-sort-column="items_count" aria-sort="<%= table_sort_aria(@q, :items_count) %>">
  <span class="inline-flex items-center gap-1">
    <%= table_sort_link(@q, :items_count, "Items", frame: "source_monitor_sources_table", default_order: :desc, secondary: ["created_at desc"], html_options: { class: "..." }) %>
    <span class="text-[11px] text-slate-400" aria-hidden="true"><%= table_sort_arrow(@q, :items_count) %></span>
  </span>
</th>
```

**Non-sortable columns (lines 171-173):**
```erb
<th scope="col" class="px-6 py-3">New Items / Day</th>
<th scope="col" class="px-6 py-3">Avg Feed Words</th>
<th scope="col" class="px-6 py-3">Avg Scraped Words</th>
```

**Challenge:** These columns are computed values (aggregates from ItemContent), not direct Source attributes. Ransack sorts on model attributes. Options:
1. Add virtual attributes/scopes on Source that Ransack can sort by
2. Use `ransacker` to define custom sort columns
3. Pre-compute and store these values on Source model (denormalization)

The existing data is computed in the controller (lines 52-64) using `ItemContent.joins(:item).group(...).average(...)`. For Ransack sorting, `ransacker` definitions would allow sorting by subquery.

## Relevant Patterns

- **Turbo Stream deletion:** Used in `SourcesController#destroy` via `TurboStreams::StreamResponder` — removes DOM elements and shows toast
- **Ransack sorting:** All via `SanitizesSearchParams` concern with `searchable_with` + `build_search_query`. Uses `sort_link` from Ransack gem through `table_sort_link` helper
- **MiniMagick:** Not currently used in the codebase. Would be a new dependency for SVG conversion
- **Active Storage attachment:** Source model uses `has_one_attached :favicon` (guarded with `if defined?(ActiveStorage)`)

## Risks

1. **SVG conversion:** Requires ImageMagick with SVG support (librsvg or Inkscape delegate). May fail in environments without proper ImageMagick setup. Should handle gracefully.
2. **Sortable computed columns:** Ransack sorting by subquery (ransacker) can be slow on large datasets. Consider adding database indexes or denormalized columns if performance is an issue.
3. **OPML banner Turbo Stream:** The panel div `#source_monitor_import_history_panel` needs a unique target. Currently has this ID, so Turbo Stream removal should work cleanly.

## Recommendations

1. **OPML Banner:** Add migration for `dismissed_at`. Create `ImportHistoryDismissals` controller (REST: POST to mark dismissed). Use `turbo_stream.remove` targeting the panel div.
2. **SVG Favicon:** Add MiniMagick gem. In Discoverer or FaviconFetchJob, detect SVG content type and convert to PNG before Active Storage attach. Keep SVG in allowed types for download but convert before storage.
3. **Activity Heading:** Restructure `_recent_activity.html.erb` to show `"domain -- Fetch #N"` as the main label. Move the domain from `url_display` into the heading.
4. **Sortable Columns:** Use `ransacker` on Source model for the three computed columns. Each ransacker defines a subquery. Follow the exact same `table_sort_link` pattern as Items/Last Fetch.
