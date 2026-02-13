# PLAN-01 Summary: dashboard-url-display-and-clickable-links

## Status: COMPLETE

## What Was Built

### Task 1: Add external_link_to helper and tests
- Added `external_link_to(label, url, **options)` public helper: renders `<a>` with `target="_blank"`, `rel="noopener noreferrer"`, and external-link SVG icon; returns plain label when URL is blank
- Added `domain_from_url(url)` public helper: extracts hostname via `URI.parse`, returns nil for blank/invalid URLs
- Added `external_link_icon` private helper: renders Heroicon external-link SVG with consistent Tailwind styling
- 7 new tests covering link rendering, nil/blank handling, custom CSS class, domain extraction, and invalid URL

### Task 2: Add URL info to recent activity query and presenter
- Added `:source_feed_url` field to `Dashboard::RecentActivity::Event` struct
- Updated `fetch_log_sql` to JOIN `sources` table and SELECT `feed_url AS source_feed_url`
- Updated `scrape_log_sql` to JOIN `items` table and SELECT `items.url AS item_url`
- Added `NULL AS source_feed_url` to `scrape_log_sql` and `item_sql` for UNION column alignment
- Updated `build_event` to pass `source_feed_url` from query results
- Added `url_display` (domain for fetches, full URL for scrapes) and `url_href` keys to presenter view models
- Added `source_domain` private method for domain extraction
- 4 new tests: fetch with domain, fetch with nil URL, failure with URL, scrape with item URL

### Task 3: Add URL to logs table presenter
- Added `url_label` public method: returns domain for fetch rows, item URL for scrape rows, nil for health checks
- Added `url_href` public method: returns full feed_url for fetches, item URL for scrapes, nil for health checks
- Added `domain_from_feed_url` private helper with URI parsing
- 6 new assertions for fetch, scrape, and health check row types

### Task 4: Update dashboard and logs views with URL display
- Dashboard `_recent_activity.html.erb`: added URL display line below event description, using `external_link_to` for clickable links
- Logs `index.html.erb`: added URL display below subject column in table rows, using `external_link_to` for clickable links
- Both use muted `text-slate-400` styling with `hover:text-blue-500` for visual consistency

### Task 5: Make external URLs clickable across views
- `sources/_row.html.erb`: feed_url in source index row is now a clickable external link
- `sources/_details.html.erb`: Feed URL header and Website URL in details hash are clickable external links
- `items/_details.html.erb`: URL and Canonical URL in details hash are clickable external links

## Files Modified
- `app/helpers/source_monitor/application_helper.rb` (external_link_to, domain_from_url, external_link_icon)
- `lib/source_monitor/dashboard/recent_activity.rb` (source_feed_url field)
- `lib/source_monitor/dashboard/queries/recent_activity_query.rb` (JOIN sources/items, source_feed_url column)
- `lib/source_monitor/dashboard/recent_activity_presenter.rb` (url_display, url_href, source_domain)
- `lib/source_monitor/logs/table_presenter.rb` (url_label, url_href, domain_from_feed_url)
- `app/views/source_monitor/dashboard/_recent_activity.html.erb` (URL display below description)
- `app/views/source_monitor/logs/index.html.erb` (URL display below subject)
- `app/views/source_monitor/sources/_row.html.erb` (clickable feed_url)
- `app/views/source_monitor/sources/_details.html.erb` (clickable feed URL, website URL)
- `app/views/source_monitor/items/_details.html.erb` (clickable URL, canonical URL)
- `test/helpers/source_monitor/application_helper_test.rb` (7 new tests)
- `test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb` (4 new tests)
- `test/lib/source_monitor/logs/table_presenter_test.rb` (6 new assertions)

## Commits
- `6fde387` feat(04-dashboard-ux): add external_link_to and domain_from_url helpers
- `527bea1` feat(04-dashboard-ux): add URL info to recent activity query and presenter
- `cd6041e` feat(04-dashboard-ux): add url_label and url_href to logs table presenter
- `5376b03` feat(04-dashboard-ux): show URL info in dashboard and logs views
- `51db3c6` feat(04-dashboard-ux): make external URLs clickable across views

## Requirements Satisfied
- REQ-22: Fetch log events display source domain; scrape log events display item URL; both success and failure events show URL info; logs table shows URL below subject column
- REQ-23: All external URLs (feed URLs, website URLs, item URLs, canonical URLs) are clickable links opening in new tabs with external-link icon indicator

## Verification Results
- `bin/rails test`: 885 runs, 2957 assertions, 0 failures, 0 errors
- `bin/rubocop`: 378 files inspected, 0 offenses

## Deviations
None. All tasks executed as specified in the plan.
