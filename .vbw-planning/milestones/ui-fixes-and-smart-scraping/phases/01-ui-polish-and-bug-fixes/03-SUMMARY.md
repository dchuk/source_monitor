---
phase: "01"
plan: "03"
title: "Recent Activity URL-First Heading"
status: complete
started_at: "2026-03-05"
completed_at: "2026-03-05"
---

## What Was Built
Restructured the Recent Activity dashboard widget so fetch events display the source domain leading the heading label (e.g., "blog.example.com -- Fetch #42") instead of showing "Fetch #42" as the heading with the domain in a separate line below. Scrape and item events remain unchanged. When the domain cannot be extracted (nil or invalid URI), the label gracefully falls back to "Fetch #N".

## Tasks Completed
- Task 1: Update RecentActivityPresenter fetch_event -- domain now leads the label as "domain -- Fetch #N", removed url_display/url_href from fetch events (commit: 529fdb6)
- Task 2: No view changes needed -- the url_display block is conditional and stops rendering for fetch events automatically
- Task 3: Updated all 7 presenter tests to assert new label format and confirm url_display/url_href are nil for fetch events (commit: 529fdb6)

## Files Modified
- `lib/source_monitor/dashboard/recent_activity_presenter.rb` -- restructured fetch_event label, removed url_display/url_href keys
- `test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb` -- updated 5 fetch event tests for new label format

## Deviations
- None

## Test Results
- 7 runs, 21 assertions, 0 failures, 0 errors (presenter test file)
- Full suite: 1222 runs, 3756 assertions, 0 failures, 16 errors (all pre-existing in unrelated tests: stalled_fetch_reconciler, solid_queue_metrics, favicon_integration, item_content, fetch_failure_subscriber)
