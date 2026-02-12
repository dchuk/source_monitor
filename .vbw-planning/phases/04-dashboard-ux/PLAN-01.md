---
phase: 4
plan: "01"
title: dashboard-url-display-and-clickable-links
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - lib/source_monitor/dashboard/recent_activity.rb
  - lib/source_monitor/dashboard/recent_activity_presenter.rb
  - lib/source_monitor/dashboard/queries/recent_activity_query.rb
  - lib/source_monitor/logs/table_presenter.rb
  - app/helpers/source_monitor/application_helper.rb
  - app/views/source_monitor/dashboard/_recent_activity.html.erb
  - app/views/source_monitor/logs/index.html.erb
  - app/views/source_monitor/sources/_row.html.erb
  - app/views/source_monitor/sources/_details.html.erb
  - app/views/source_monitor/items/_details.html.erb
  - test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb
  - test/lib/source_monitor/logs/table_presenter_test.rb
  - test/helpers/source_monitor/application_helper_test.rb
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/logs/table_presenter_test.rb` exits 0 with 0 failures"
    - "Running `bin/rails test` exits 0 with 874+ runs and 0 failures"
    - "Running `bin/rubocop` exits 0 with 0 offenses"
  artifacts:
    - path: "lib/source_monitor/dashboard/recent_activity.rb"
      provides: "Event struct with source_feed_url field for domain display"
      contains: "source_feed_url"
    - path: "lib/source_monitor/dashboard/recent_activity_presenter.rb"
      provides: "Fetch events include source domain, scrape events include item URL (REQ-22)"
      contains: "source_domain"
    - path: "lib/source_monitor/dashboard/queries/recent_activity_query.rb"
      provides: "SQL JOINs to pull feed_url for fetch events and item url for scrape events"
      contains: "feed_url"
    - path: "lib/source_monitor/logs/table_presenter.rb"
      provides: "Row#url_label returns domain for fetch rows, item URL for scrape rows"
      contains: "url_label"
    - path: "app/helpers/source_monitor/application_helper.rb"
      provides: "external_link_to helper that adds target=_blank, rel=noopener, and external-link icon"
      contains: "external_link_to"
    - path: "app/views/source_monitor/dashboard/_recent_activity.html.erb"
      provides: "URL info displayed below description for fetch and scrape events"
      contains: "url_display"
    - path: "app/views/source_monitor/sources/_row.html.erb"
      provides: "Feed URL in source row is a clickable external link"
      contains: "external_link_to"
    - path: "app/views/source_monitor/sources/_details.html.erb"
      provides: "Website URL and Feed URL are clickable external links"
      contains: "external_link_to"
    - path: "app/views/source_monitor/items/_details.html.erb"
      provides: "Item URL and Canonical URL are clickable external links"
      contains: "external_link_to"
  key_links:
    - from: "recent_activity_query.rb#fetch_log_sql"
      to: "REQ-22"
      via: "JOIN sources to pull feed_url, displayed as domain on dashboard"
    - from: "recent_activity_query.rb#scrape_log_sql"
      to: "REQ-22"
      via: "JOIN items to pull item url, displayed on dashboard"
    - from: "application_helper.rb#external_link_to"
      to: "REQ-23"
      via: "All external URLs use this helper for target=_blank + external-link icon"
    - from: "sources/_row.html.erb"
      to: "REQ-23"
      via: "Feed URL in source index row is clickable"
    - from: "sources/_details.html.erb"
      to: "REQ-23"
      via: "Website URL and feed URL on source detail page are clickable"
    - from: "items/_details.html.erb"
      to: "REQ-23"
      via: "Item URL and canonical URL are clickable"
---
<objective>
Show source domain (RSS fetch logs) and item URL (scrape logs) in dashboard recent activity and logs table for both success and failure entries (REQ-22). Make all external URLs (feed URLs, website URLs, item URLs) clickable links that open in a new tab with an external-link icon indicator across dashboard, sources index, source detail, and item detail views (REQ-23).
</objective>
<context>
@lib/source_monitor/dashboard/recent_activity.rb -- Event struct with keyword_init. Currently has: type, id, occurred_at, success, items_created, items_updated, scraper_adapter, item_title, item_url, source_name, source_id. Add `source_feed_url` field so the presenter can extract the domain for fetch events. The `item_url` field already exists but is currently NULL for scrape events in the SQL query.

@lib/source_monitor/dashboard/recent_activity_presenter.rb -- Transforms Event structs into view-model hashes with keys: label, description, status, type, time, path. `fetch_event` currently shows "N created / N updated" as description. Add `url_display` key to the hash: for fetch events, extract domain from `event.source_feed_url` using `URI.parse(url).host`; for scrape events, use `event.item_url`. Both success and failure events get URL info since the source/item is known regardless of outcome.

@lib/source_monitor/dashboard/queries/recent_activity_query.rb -- Raw SQL UNION query. `fetch_log_sql` currently selects `NULL AS source_name` and `NULL AS item_url`. Change: (1) JOIN sources table to fetch_logs and SELECT `feed_url AS source_feed_url` (new column in UNION), (2) For scrape_log_sql, JOIN items table and SELECT `items.url AS item_url` (currently NULL). Add `source_feed_url` to the outer SELECT and `build_event`. All three sub-queries must have matching column count, so add `NULL AS source_feed_url` to scrape_log_sql and item_sql.

@lib/source_monitor/logs/table_presenter.rb -- Row class wraps LogEntry records. Add `url_label` method: for fetch rows, extract domain from `entry.source&.feed_url`; for scrape rows, return `entry.item&.url`. This will be displayed in the logs table. The LogEntry model already has `belongs_to :source` and `belongs_to :item` so the associations are available.

@app/helpers/source_monitor/application_helper.rb -- Add `external_link_to(label, url, **options)` helper that wraps `link_to` with `target: "_blank"`, `rel: "noopener noreferrer"`, and appends a small external-link SVG icon. This DRYs up the pattern used across all views. The helper should handle nil/blank URLs gracefully (return label as plain text). Include Tailwind classes for consistent styling.

@app/views/source_monitor/dashboard/_recent_activity.html.erb -- Currently shows `event[:description]` as text. Add `event[:url_display]` rendering below the description as a smaller, muted line showing the URL/domain. Use the external_link_to helper to make it clickable. Only render if url_display is present.

@app/views/source_monitor/logs/index.html.erb -- The table has columns: Started, Type, Subject, Source, HTTP/Adapter, Result, Metrics, detail link. The URL info fits naturally into the existing Subject column as a second line below the primary_label, similar to how the sources row shows feed_url below the name. Use `row.url_label` for this.

@app/views/source_monitor/sources/_row.html.erb -- Line 32: `<div class="text-xs text-slate-500 truncate max-w-xs"><%= source.feed_url %></div>` -- plain text. Replace with `external_link_to` helper call, truncating the display text.

@app/views/source_monitor/sources/_details.html.erb -- Line 28: `Feed URL: <%= source.feed_url %>` -- plain text. Replace with external_link_to. Line 140: `"Website" => (source.website_url.presence || "-")` -- plain text in details hash. Replace with external_link_to call for the value.

@app/views/source_monitor/items/_details.html.erb -- Lines 56-57: `"URL" => item.url` and `"Canonical URL" => item.canonical_url || "-"` -- plain text in details hash. Replace both with external_link_to helper calls.

@test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb -- 2 existing tests. Add tests for: (a) fetch event includes url_display with domain from source_feed_url, (b) scrape event includes url_display with item URL, (c) fetch event with nil source_feed_url omits url_display, (d) failure fetch event still includes url_display.

@test/lib/source_monitor/logs/table_presenter_test.rb -- 1 existing test with comprehensive assertions. Add assertions for `url_label` on fetch_row (domain from source feed_url) and scrape_row (item URL).

**Rationale:** The dashboard is the primary monitoring surface. When a fetch fails, operators need to immediately see which feed URL was involved without clicking through. Similarly, scrape failures should show the item URL. Making all external URLs clickable with new-tab behavior follows standard UX conventions for dashboards that reference external resources.
</context>
<tasks>
<task type="auto">
  <name>add-external-link-helper-and-tests</name>
  <files>
    app/helpers/source_monitor/application_helper.rb
    test/helpers/source_monitor/application_helper_test.rb
  </files>
  <action>
**Add `external_link_to` helper to `app/helpers/source_monitor/application_helper.rb`:**

Add the following public method before the `private` keyword (around line 215):

```ruby
# Renders a clickable link that opens in a new tab with an external-link icon.
# Returns the label as plain text if the URL is blank.
def external_link_to(label, url, **options)
  return label if url.blank?

  css = options.delete(:class) || "text-blue-600 hover:text-blue-500"
  link_to(url, target: "_blank", rel: "noopener noreferrer", class: css, title: url, **options) do
    safe_join([label, " ", external_link_icon])
  end
end
```

Also add a private `external_link_icon` method after the `private` keyword:

```ruby
def external_link_icon
  tag.svg(
    class: "inline-block h-3 w-3 text-slate-400",
    xmlns: "http://www.w3.org/2000/svg",
    fill: "none",
    viewBox: "0 0 24 24",
    stroke_width: "2",
    stroke: "currentColor",
    aria: { hidden: "true" }
  ) do
    safe_join([
      tag.path(
        stroke_linecap: "round",
        stroke_linejoin: "round",
        d: "M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
      )
    ])
  end
end
```

Also add a public `domain_from_url(url)` helper (used by presenters and views) before the `private` keyword:

```ruby
# Extracts the domain from a URL, returning nil if parsing fails.
def domain_from_url(url)
  return nil if url.blank?

  URI.parse(url.to_s).host
rescue URI::InvalidURIError
  nil
end
```

**Add/update test file `test/helpers/source_monitor/application_helper_test.rb`:**

Create or update the test file with tests for `external_link_to` and `domain_from_url`:

```ruby
# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ApplicationHelperTest < ActionView::TestCase
    include SourceMonitor::ApplicationHelper

    test "external_link_to renders link with target blank and icon" do
      result = external_link_to("Example", "https://example.com")
      assert_includes result, 'target="_blank"'
      assert_includes result, 'rel="noopener noreferrer"'
      assert_includes result, "Example"
      assert_includes result, "<svg"
    end

    test "external_link_to returns plain label when url is blank" do
      result = external_link_to("No URL", nil)
      assert_equal "No URL", result
    end

    test "external_link_to returns plain label when url is empty string" do
      result = external_link_to("No URL", "")
      assert_equal "No URL", result
    end

    test "external_link_to accepts custom css class" do
      result = external_link_to("Link", "https://example.com", class: "custom-class")
      assert_includes result, "custom-class"
    end

    test "domain_from_url extracts host from valid URL" do
      assert_equal "example.com", domain_from_url("https://example.com/path")
      assert_equal "blog.example.org", domain_from_url("https://blog.example.org/feed.xml")
    end

    test "domain_from_url returns nil for blank URL" do
      assert_nil domain_from_url(nil)
      assert_nil domain_from_url("")
    end

    test "domain_from_url returns nil for invalid URL" do
      assert_nil domain_from_url("not a url %%%")
    end
  end
end
```
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/helpers/source_monitor/application_helper_test.rb` -- all tests pass. Run `bin/rubocop app/helpers/source_monitor/application_helper.rb test/helpers/source_monitor/application_helper_test.rb` -- 0 offenses.
  </verify>
  <done>
external_link_to helper renders links with target=_blank, rel=noopener noreferrer, and external-link SVG icon. domain_from_url extracts hostnames from URLs. Both handle nil/blank gracefully. 7 tests pass. REQ-23 foundation established.
  </done>
</task>
<task type="auto">
  <name>add-url-info-to-recent-activity-query-and-presenter</name>
  <files>
    lib/source_monitor/dashboard/recent_activity.rb
    lib/source_monitor/dashboard/queries/recent_activity_query.rb
    lib/source_monitor/dashboard/recent_activity_presenter.rb
    test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb
  </files>
  <action>
**Step 1: Add `source_feed_url` to the Event struct in `lib/source_monitor/dashboard/recent_activity.rb`:**

Add `:source_feed_url` to the Struct fields, after `:source_id`:

```ruby
Event = Struct.new(
  :type,
  :id,
  :occurred_at,
  :success,
  :items_created,
  :items_updated,
  :scraper_adapter,
  :item_title,
  :item_url,
  :source_name,
  :source_id,
  :source_feed_url,
  keyword_init: true
)
```

**Step 2: Update `lib/source_monitor/dashboard/queries/recent_activity_query.rb`:**

(a) Add `source_feed_url` to the outer SELECT in `unified_sql_template`:
```ruby
SELECT resource_type,
       resource_id,
       occurred_at,
       success_flag,
       items_created,
       items_updated,
       scraper_adapter,
       item_title,
       item_url,
       source_name,
       source_id,
       source_feed_url
FROM (
```

(b) Update `fetch_log_sql` to JOIN sources and select feed_url:
```ruby
def fetch_log_sql
  <<~SQL
    SELECT
      '#{EVENT_TYPE_FETCH}' AS resource_type,
      #{SourceMonitor::FetchLog.quoted_table_name}.id AS resource_id,
      #{SourceMonitor::FetchLog.quoted_table_name}.started_at AS occurred_at,
      CASE WHEN #{SourceMonitor::FetchLog.quoted_table_name}.success THEN 1 ELSE 0 END AS success_flag,
      #{SourceMonitor::FetchLog.quoted_table_name}.items_created AS items_created,
      #{SourceMonitor::FetchLog.quoted_table_name}.items_updated AS items_updated,
      NULL AS scraper_adapter,
      NULL AS item_title,
      NULL AS item_url,
      #{SourceMonitor::Source.quoted_table_name}.#{quoted_source_name} AS source_name,
      #{SourceMonitor::FetchLog.quoted_table_name}.source_id AS source_id,
      #{SourceMonitor::Source.quoted_table_name}.feed_url AS source_feed_url
    FROM #{SourceMonitor::FetchLog.quoted_table_name}
    LEFT JOIN #{SourceMonitor::Source.quoted_table_name}
      ON #{SourceMonitor::Source.quoted_table_name}.id = #{SourceMonitor::FetchLog.quoted_table_name}.source_id
  SQL
end
```

(c) Update `scrape_log_sql` to also JOIN items and select item url, plus add NULL source_feed_url:
```ruby
def scrape_log_sql
  <<~SQL
    SELECT
      '#{EVENT_TYPE_SCRAPE}' AS resource_type,
      #{SourceMonitor::ScrapeLog.quoted_table_name}.id AS resource_id,
      #{SourceMonitor::ScrapeLog.quoted_table_name}.started_at AS occurred_at,
      CASE WHEN #{SourceMonitor::ScrapeLog.quoted_table_name}.success THEN 1 ELSE 0 END AS success_flag,
      NULL AS items_created,
      NULL AS items_updated,
      #{SourceMonitor::ScrapeLog.quoted_table_name}.scraper_adapter AS scraper_adapter,
      NULL AS item_title,
      #{SourceMonitor::Item.quoted_table_name}.url AS item_url,
      #{SourceMonitor::Source.quoted_table_name}.#{quoted_source_name} AS source_name,
      #{SourceMonitor::ScrapeLog.quoted_table_name}.source_id AS source_id,
      NULL AS source_feed_url
    FROM #{SourceMonitor::ScrapeLog.quoted_table_name}
    LEFT JOIN #{SourceMonitor::Source.quoted_table_name}
      ON #{SourceMonitor::Source.quoted_table_name}.id = #{SourceMonitor::ScrapeLog.quoted_table_name}.source_id
    LEFT JOIN #{SourceMonitor::Item.quoted_table_name}
      ON #{SourceMonitor::Item.quoted_table_name}.id = #{SourceMonitor::ScrapeLog.quoted_table_name}.item_id
  SQL
end
```

(d) Update `item_sql` to add NULL source_feed_url:
```ruby
# Add after the source_id line:
NULL AS source_feed_url
```

(e) Update `build_event` to include the new field:
```ruby
source_feed_url: row["source_feed_url"]
```

**Step 3: Update `lib/source_monitor/dashboard/recent_activity_presenter.rb`:**

(a) Add `url_display` and `url_href` keys to `fetch_event`:
```ruby
def fetch_event(event)
  domain = source_domain(event.source_feed_url)
  {
    label: "Fetch ##{event.id}",
    description: "#{event.items_created.to_i} created / #{event.items_updated.to_i} updated",
    status: event.success? ? :success : :failure,
    type: :fetch,
    time: event.occurred_at,
    path: url_helpers.fetch_log_path(event.id),
    url_display: domain,
    url_href: event.source_feed_url
  }
end
```

(b) Add `url_display` and `url_href` keys to `scrape_event`:
```ruby
def scrape_event(event)
  {
    label: "Scrape ##{event.id}",
    description: (event.scraper_adapter.presence || "Scraper"),
    status: event.success? ? :success : :failure,
    type: :scrape,
    time: event.occurred_at,
    path: url_helpers.scrape_log_path(event.id),
    url_display: event.item_url,
    url_href: event.item_url
  }
end
```

(c) Add private `source_domain` method:
```ruby
def source_domain(feed_url)
  return nil if feed_url.blank?

  URI.parse(feed_url.to_s).host
rescue URI::InvalidURIError
  nil
end
```

**Step 4: Update tests in `test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb`:**

Add the following tests after the existing ones:

```ruby
test "fetch event includes source domain as url_display" do
  event = SourceMonitor::Dashboard::RecentActivity::Event.new(
    type: :fetch_log,
    id: 10,
    occurred_at: Time.current,
    success: true,
    items_created: 2,
    items_updated: 0,
    source_feed_url: "https://blog.example.com/feed.xml"
  )

  presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
    [event],
    url_helpers: SourceMonitor::Engine.routes.url_helpers
  )

  result = presenter.to_a.first
  assert_equal "blog.example.com", result[:url_display]
  assert_equal "https://blog.example.com/feed.xml", result[:url_href]
end

test "fetch event with nil source_feed_url has nil url_display" do
  event = SourceMonitor::Dashboard::RecentActivity::Event.new(
    type: :fetch_log,
    id: 11,
    occurred_at: Time.current,
    success: false,
    items_created: 0,
    items_updated: 0,
    source_feed_url: nil
  )

  presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
    [event],
    url_helpers: SourceMonitor::Engine.routes.url_helpers
  )

  result = presenter.to_a.first
  assert_nil result[:url_display]
  assert_equal :failure, result[:status]
end

test "failure fetch event still includes url_display" do
  event = SourceMonitor::Dashboard::RecentActivity::Event.new(
    type: :fetch_log,
    id: 12,
    occurred_at: Time.current,
    success: false,
    items_created: 0,
    items_updated: 0,
    source_feed_url: "https://failing-feed.example.org/rss"
  )

  presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
    [event],
    url_helpers: SourceMonitor::Engine.routes.url_helpers
  )

  result = presenter.to_a.first
  assert_equal "failing-feed.example.org", result[:url_display]
  assert_equal :failure, result[:status]
end

test "scrape event includes item url as url_display" do
  event = SourceMonitor::Dashboard::RecentActivity::Event.new(
    type: :scrape_log,
    id: 20,
    occurred_at: Time.current,
    success: true,
    scraper_adapter: "readability",
    item_url: "https://example.com/articles/42"
  )

  presenter = SourceMonitor::Dashboard::RecentActivityPresenter.new(
    [event],
    url_helpers: SourceMonitor::Engine.routes.url_helpers
  )

  result = presenter.to_a.first
  assert_equal "https://example.com/articles/42", result[:url_display]
  assert_equal "https://example.com/articles/42", result[:url_href]
end
```
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb` -- all 6 tests pass. Run `bin/rubocop lib/source_monitor/dashboard/recent_activity.rb lib/source_monitor/dashboard/recent_activity_presenter.rb lib/source_monitor/dashboard/queries/recent_activity_query.rb` -- 0 offenses.
  </verify>
  <done>
RecentActivityQuery now JOINs sources for fetch logs (pulling feed_url) and JOINs items for scrape logs (pulling item url). Presenter extracts domain for fetch events and passes through item URL for scrape events. Both success and failure events include URL info. 6 tests pass. REQ-22 core data layer complete.
  </done>
</task>
<task type="auto">
  <name>add-url-to-logs-table-presenter</name>
  <files>
    lib/source_monitor/logs/table_presenter.rb
    test/lib/source_monitor/logs/table_presenter_test.rb
  </files>
  <action>
**Step 1: Add `url_label` and `url_href` methods to `lib/source_monitor/logs/table_presenter.rb` Row class:**

Add these public methods after the `primary_path` method (around line 62):

```ruby
def url_label
  if fetch?
    domain_from_feed_url
  elsif scrape?
    entry.item&.url
  end
end

def url_href
  if fetch?
    entry.source&.feed_url
  elsif scrape?
    entry.item&.url
  end
end
```

Add a private helper method after the existing `attr_reader` line (around line 144):

```ruby
def domain_from_feed_url
  feed_url = entry.source&.feed_url
  return nil if feed_url.blank?

  URI.parse(feed_url.to_s).host
rescue URI::InvalidURIError
  nil
end
```

**Step 2: Update tests in `test/lib/source_monitor/logs/table_presenter_test.rb`:**

Add assertions for `url_label` and `url_href` inside the existing "builds typed row view models" test:

After the fetch_row assertions block (around line 91), add:
```ruby
assert_match(/presenter-source\.test/, fetch_row.url_label) if @source.feed_url.present?
assert_equal @source.feed_url, fetch_row.url_href
```

Wait -- the test creates a source via `create_source!(name: "Presenter Source")`. Check what feed_url that gives. The factory likely sets a default feed_url. Add these assertions:

For the fetch_row section, after `assert_equal source_path(@source), fetch_row.primary_path`, add:
```ruby
assert_equal URI.parse(@source.feed_url).host, fetch_row.url_label
assert_equal @source.feed_url, fetch_row.url_href
```

For the scrape_row section, after `assert_equal item_path(@item), scrape_row.primary_path`, add:
```ruby
assert_equal "https://example.com/articles/presenter", scrape_row.url_label
assert_equal "https://example.com/articles/presenter", scrape_row.url_href
```

For the health_row section, after the last assertion, add:
```ruby
assert_nil health_row.url_label
assert_nil health_row.url_href
```
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/logs/table_presenter_test.rb` -- all tests pass. Run `bin/rubocop lib/source_monitor/logs/table_presenter.rb` -- 0 offenses.
  </verify>
  <done>
TablePresenter::Row now provides url_label (domain for fetches, full URL for scrapes) and url_href for linking. Health check rows return nil. Tests updated with assertions for all three row types. REQ-22 logs table data layer complete.
  </done>
</task>
<task type="auto">
  <name>update-dashboard-and-logs-views-with-url-display</name>
  <files>
    app/views/source_monitor/dashboard/_recent_activity.html.erb
    app/views/source_monitor/logs/index.html.erb
  </files>
  <action>
**Step 1: Update `app/views/source_monitor/dashboard/_recent_activity.html.erb`:**

After the description line (line 22-23), add a URL display line. Replace the description block:

Current (lines 21-23):
```erb
<div class="mt-1 text-xs text-slate-500">
  <%= event[:description].presence || "No additional details recorded." %>
</div>
```

Replace with:
```erb
<div class="mt-1 text-xs text-slate-500">
  <%= event[:description].presence || "No additional details recorded." %>
</div>
<% if event[:url_display].present? %>
  <div class="mt-0.5 text-xs text-slate-400 truncate max-w-sm" data-testid="event-url-display">
    <% if event[:url_href].present? %>
      <%= external_link_to event[:url_display], event[:url_href], class: "text-slate-400 hover:text-blue-500" %>
    <% else %>
      <%= event[:url_display] %>
    <% end %>
  </div>
<% end %>
```

**Step 2: Update `app/views/source_monitor/logs/index.html.erb`:**

In the table body, update the Subject column (lines 131-136) to also show the URL below the primary label:

Current:
```erb
<td class="px-6 py-4 text-sm">
  <% if row.primary_path %>
    <%= link_to row.primary_label, row.primary_path, class: "text-blue-600 hover:text-blue-500" %>
  <% else %>
    <%= row.primary_label %>
  <% end %>
</td>
```

Replace with:
```erb
<td class="px-6 py-4 text-sm">
  <% if row.primary_path %>
    <%= link_to row.primary_label, row.primary_path, class: "text-blue-600 hover:text-blue-500" %>
  <% else %>
    <%= row.primary_label %>
  <% end %>
  <% if row.url_label.present? %>
    <div class="mt-0.5 text-xs text-slate-400 truncate max-w-xs">
      <% if row.url_href.present? %>
        <%= external_link_to row.url_label, row.url_href, class: "text-slate-400 hover:text-blue-500" %>
      <% else %>
        <%= row.url_label %>
      <% end %>
    </div>
  <% end %>
</td>
```

This preserves the existing layout while adding URL context below the subject line, using the same pattern as the sources index row (feed URL below source name).
  </action>
  <verify>
Run `bin/rubocop` on the modified .erb files (RuboCop may not lint .erb but confirm no syntax errors). Run `bin/rails test` to ensure no rendering errors. Visually inspect: the URL line should appear below the description/subject in both the dashboard recent activity panel and the logs table.
  </verify>
  <done>
Dashboard recent activity shows source domain for fetch events and item URL for scrape events. Logs table shows URL info below the subject column. Both use external_link_to for clickable links with new-tab behavior. Layout preserved with muted styling. REQ-22 view layer complete.
  </done>
</task>
<task type="auto">
  <name>make-external-urls-clickable-across-views</name>
  <files>
    app/views/source_monitor/sources/_row.html.erb
    app/views/source_monitor/sources/_details.html.erb
    app/views/source_monitor/items/_details.html.erb
  </files>
  <action>
**Step 1: Update `app/views/source_monitor/sources/_row.html.erb`:**

Replace line 32:
```erb
<div class="text-xs text-slate-500 truncate max-w-xs"><%= source.feed_url %></div>
```

With:
```erb
<div class="text-xs text-slate-500 truncate max-w-xs"><%= external_link_to source.feed_url, source.feed_url, class: "text-slate-500 hover:text-blue-500" %></div>
```

**Step 2: Update `app/views/source_monitor/sources/_details.html.erb`:**

(a) Replace line 28:
```erb
<p class="mt-2 text-sm text-slate-500">Feed URL: <%= source.feed_url %></p>
```

With:
```erb
<p class="mt-2 text-sm text-slate-500">Feed URL: <%= external_link_to source.feed_url, source.feed_url, class: "text-slate-500 hover:text-blue-500" %></p>
```

(b) In the details hash (around line 140), replace:
```ruby
"Website" => (source.website_url.presence || "\u2014"),
```

With:
```ruby
"Website" => (source.website_url.present? ? external_link_to(source.website_url, source.website_url, class: "text-slate-900 hover:text-blue-500") : "\u2014"),
```

Note: Since the details hash values are rendered via `<%= value %>`, and external_link_to returns an html_safe string from link_to, this will work correctly. However, you may need to use `raw` or ensure the helper returns `html_safe` content. Since `link_to` already returns safe HTML, this should work.

**Step 3: Update `app/views/source_monitor/items/_details.html.erb`:**

In the details hash (around lines 56-57), replace:
```ruby
"URL" => item.url,
"Canonical URL" => item.canonical_url || "\u2014",
```

With:
```ruby
"URL" => (item.url.present? ? external_link_to(item.url, item.url, class: "text-slate-900 hover:text-blue-500") : "\u2014"),
"Canonical URL" => (item.canonical_url.present? ? external_link_to(item.canonical_url, item.canonical_url, class: "text-slate-900 hover:text-blue-500") : "\u2014"),
```

**Step 4: Full suite verification:**

Run `bin/rails test` -- all 874+ tests pass with 0 failures.
Run `bin/rubocop` -- 0 offenses.

Check that no existing test assertions break due to the HTML changes (controller integration tests that assert on response body content may need attention if they check for exact text matches on URLs).
  </action>
  <verify>
Run `bin/rails test` -- all tests pass. Run `bin/rubocop` -- 0 offenses. Grep for `external_link_to` in the three modified view files to confirm all external URLs are now wrapped. Grep for `target="_blank"` in the rendered output would confirm new-tab behavior.
  </verify>
  <done>
All external URLs are now clickable across source index rows (feed URL), source detail page (feed URL, website URL), and item detail page (URL, canonical URL). Links open in new tab with external-link icon indicator. REQ-23 fully satisfied. Full test suite passes, RuboCop clean.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/helpers/source_monitor/application_helper_test.rb` -- 7 tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb` -- 6 tests pass
3. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/logs/table_presenter_test.rb` -- tests pass with url_label/url_href assertions
4. `bin/rails test` -- 874+ runs, 0 failures
5. `bin/rubocop` -- 0 offenses
6. `grep -n 'external_link_to' app/helpers/source_monitor/application_helper.rb` -- method defined
7. `grep -n 'source_feed_url' lib/source_monitor/dashboard/recent_activity.rb` -- field in Event struct
8. `grep -n 'url_display' lib/source_monitor/dashboard/recent_activity_presenter.rb` -- key in view model hash
9. `grep -n 'feed_url' lib/source_monitor/dashboard/queries/recent_activity_query.rb` -- SELECT in fetch_log_sql
10. `grep -n 'url_label' lib/source_monitor/logs/table_presenter.rb` -- method on Row
11. `grep -n 'external_link_to' app/views/source_monitor/sources/_row.html.erb` -- feed URL clickable
12. `grep -n 'external_link_to' app/views/source_monitor/sources/_details.html.erb` -- website/feed URL clickable
13. `grep -n 'external_link_to' app/views/source_monitor/items/_details.html.erb` -- item URL clickable
14. `grep -rn 'target="_blank"' app/views/source_monitor/dashboard/_recent_activity.html.erb` -- new-tab links via helper
</verification>
<success_criteria>
- Fetch log events on the dashboard display the source domain extracted from feed_url (REQ-22)
- Scrape log events on the dashboard display the item URL being scraped (REQ-22)
- Both success and failure fetch/scrape events show URL info (REQ-22)
- Logs table shows URL info below the subject column for fetch and scrape entries (REQ-22)
- external_link_to helper renders links with target=_blank, rel=noopener noreferrer, external-link SVG icon (REQ-23)
- Source index row feed URLs are clickable external links (REQ-23)
- Source detail page feed URL and website URL are clickable external links (REQ-23)
- Item detail page URL and canonical URL are clickable external links (REQ-23)
- Existing dashboard layout is preserved (no structural changes to grid/flex layout)
- All existing tests pass with no regressions
- New tests cover external_link_to, domain_from_url, presenter url_display, and table presenter url_label
- RuboCop clean
</success_criteria>
<output>
.vbw-planning/phases/04-dashboard-ux/PLAN-01-SUMMARY.md
</output>
