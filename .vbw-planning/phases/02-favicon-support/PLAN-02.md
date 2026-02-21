---
phase: 2
plan: 2
title: "Favicon View Display with Fallback Placeholder"
wave: 1
depends_on: []
must_haves:
  - "source_favicon_tag helper method exists in ApplicationHelper rendering favicon image or initials placeholder"
  - "Sources index _row.html.erb displays favicon next to source name"
  - "Sources show _details.html.erb displays favicon next to source name heading"
  - "Placeholder shows first letter of source name in a colored circle when no favicon"
  - "No errors when ActiveStorage is not defined (graceful degradation)"
  - "All existing view tests still pass"
  - "bin/rubocop zero offenses"
skills_used: []
---

# Plan 02: Favicon View Display with Fallback Placeholder

## Objective

Display source favicons in the UI next to source names with a graceful fallback placeholder when no favicon is available. REQ-FAV-04.

## Context

- `@app/views/source_monitor/sources/_row.html.erb` -- source list row, name displayed at lines 26-31
- `@app/views/source_monitor/sources/_details.html.erb` -- source show page, name at line 12, heading section lines 10-29
- `@app/helpers/source_monitor/application_helper.rb` -- helper module with existing badge/icon helpers
- `@app/models/source_monitor/item_content.rb` -- ActiveStorage guard pattern reference

This plan has NO file overlap with Plan 01 (which modifies configuration.rb, source.rb model, source_monitor.rb, and creates new lib/job files). This plan only modifies view templates and the helper module.

## Tasks

### Task 1: Create source_favicon_tag helper method

**Files:** `app/helpers/source_monitor/application_helper.rb`

Add a public helper method that renders either the favicon image or a fallback placeholder. Insert before the `private` keyword (line 235).

```ruby
# Renders the source favicon as an <img> tag or a colored-circle initials
# placeholder when no favicon is attached.  Handles the case where
# ActiveStorage is not loaded (host app without AS).
#
# Options:
#   size: pixel dimension for width/height (default: 24)
#   class: additional CSS classes
def source_favicon_tag(source, size: 24, **options)
  css = options.delete(:class) || ""

  if favicon_attached?(source)
    favicon_image_tag(source, size: size, css: css)
  else
    favicon_placeholder_tag(source, size: size, css: css)
  end
end
```

Add the following private methods after the existing `private` keyword:

```ruby
def favicon_attached?(source)
  defined?(ActiveStorage) &&
    source.respond_to?(:favicon) &&
    source.favicon.attached?
end

def favicon_image_tag(source, size:, css:)
  # Serve the raw favicon and let CSS constrain dimensions.
  # No Active Storage variants (image_processing gem not in gemspec).
  url = url_for(source.favicon)

  image_tag(url,
    alt: "#{source.name} favicon",
    width: size,
    height: size,
    class: "rounded object-contain #{css}".strip,
    style: "max-width: #{size}px; max-height: #{size}px;",
    loading: "lazy")
rescue StandardError
  # Fallback if URL generation fails (blob missing, etc.)
  favicon_placeholder_tag(source, size: size, css: css)
end

def favicon_placeholder_tag(source, size:, css:)
  initial = source.name.to_s.strip.first&.upcase || "?"
  # Generate a consistent color based on the source name
  hue = source.name.to_s.bytes.sum % 360
  bg_color = "hsl(#{hue}, 45%, 65%)"

  content_tag(:span,
    initial,
    class: "inline-flex items-center justify-center rounded-full text-white font-semibold #{css}".strip,
    style: "width: #{size}px; height: #{size}px; background-color: #{bg_color}; font-size: #{(size * 0.5).round}px; line-height: #{size}px;",
    title: source.name,
    "aria-hidden": "true")
end
```

**Tests:** `test/helpers/source_monitor/favicon_helper_test.rb`

Create a helper test:
- Test source_favicon_tag with no favicon attached: returns span with initial letter
- Test source_favicon_tag placeholder uses first letter of source name uppercased
- Test source_favicon_tag placeholder handles blank name gracefully (shows "?")
- Test source_favicon_tag generates consistent color from name (same name = same hue)
- Test source_favicon_tag with different size parameter: style contains correct dimensions
- Test favicon_attached? returns false when ActiveStorage not loaded (mock respond_to?)
- Test favicon_attached? returns false when favicon not attached

### Task 2: Add favicon to sources index row

**Files:** `app/views/source_monitor/sources/_row.html.erb`

Modify the source name cell (lines 25-33) to include the favicon before the name. Replace the existing name display:

Current (lines 25-32):
```erb
<td class="px-6 py-4">
    <div class="font-medium text-slate-900">
      <%= link_to source.name,
            source_monitor.source_path(source),
            class: "text-slate-900 hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
            data: { turbo_frame: "_top" } %>
    </div>
    <div class="text-xs text-slate-500 truncate max-w-xs"><%= external_link_to source.feed_url, source.feed_url, class: "text-slate-500 hover:text-blue-500" %></div>
  </td>
```

Replace with:
```erb
<td class="px-6 py-4">
    <div class="flex items-center gap-3">
      <%= source_favicon_tag(source, size: 24) %>
      <div>
        <div class="font-medium text-slate-900">
          <%= link_to source.name,
                source_monitor.source_path(source),
                class: "text-slate-900 hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                data: { turbo_frame: "_top" } %>
        </div>
        <div class="text-xs text-slate-500 truncate max-w-xs"><%= external_link_to source.feed_url, source.feed_url, class: "text-slate-500 hover:text-blue-500" %></div>
      </div>
    </div>
  </td>
```

The key change: wrap name and feed_url in a flex container with the favicon tag.

**Tests:** Covered by existing system tests for sources index (they should still pass as content is the same, just with added favicon element). The helper test from Task 1 covers the rendering logic.

### Task 3: Add favicon to source show page

**Files:** `app/views/source_monitor/sources/_details.html.erb`

Modify the source name heading section (lines 10-13). Currently:

```erb
<div>
  <h1 class="text-3xl font-semibold text-slate-900"><%= source.name %></h1>
```

Replace with:
```erb
<div>
  <div class="flex items-center gap-4">
    <%= source_favicon_tag(source, size: 40) %>
    <h1 class="text-3xl font-semibold text-slate-900"><%= source.name %></h1>
  </div>
```

This adds a larger 40px favicon next to the source name on the detail page.

**Tests:** Covered by existing system tests. The helper handles all edge cases.

### Task 4: Add favicon to import session source rows (if applicable)

**Files:** No changes needed.

Review the import session views. The import wizard previews sources that don't exist yet (they are parsed from OPML), so they won't have favicons. No view changes needed for import sessions -- favicons will appear after sources are created and the job runs.

This task is a no-op but documents the explicit decision not to modify import views.

**Tests:** No additional tests needed.

## Files

| Action | Path |
|--------|------|
| MODIFY | `app/helpers/source_monitor/application_helper.rb` |
| MODIFY | `app/views/source_monitor/sources/_row.html.erb` |
| MODIFY | `app/views/source_monitor/sources/_details.html.erb` |
| CREATE | `test/helpers/source_monitor/favicon_helper_test.rb` |

## Verification

```bash
bin/rails test test/helpers/source_monitor/favicon_helper_test.rb
bin/rails test test/system/sources_test.rb
bin/rubocop app/helpers/source_monitor/application_helper.rb app/views/source_monitor/sources/_row.html.erb app/views/source_monitor/sources/_details.html.erb
```

## Success Criteria

- source_favicon_tag renders favicon image when attached, initials placeholder when not
- Placeholder uses first letter of source name with consistent HSL color
- Sources index shows favicon in each row next to source name
- Source show page shows larger favicon next to name heading
- No errors when ActiveStorage is not available
- No errors when favicon is not attached (most common case initially)
- All existing system/integration tests pass
- Zero RuboCop offenses
