---
phase: "01"
plan: "03"
title: "Recent Activity URL-First Heading"
wave: 1
depends_on: []
must_haves:
  - "URL/domain leads the heading row for fetch events"
  - "Format: 'domain -- Fetch #N FETCH'"
  - "Existing badge and stats layout preserved"
  - "Tests for updated presenter output"
---

## Tasks

### Task 1: Update RecentActivityPresenter fetch_event

Restructure the fetch event view model so the domain/URL leads the label.

**Files:**
- Modify: `lib/source_monitor/dashboard/recent_activity_presenter.rb` — change `fetch_event` method

**Details:**
- Current: `label: "Fetch ##{event.id}"`, `url_display: domain`
- New: `label: "#{domain} — Fetch ##{event.id}"` where domain comes from `source_domain(event.source_feed_url)`
- If domain is nil, fall back to `"Fetch ##{event.id}"` (no change)
- Remove `url_display` and `url_href` from fetch events since URL is now in the heading
- Keep scrape and item events unchanged

### Task 2: Update recent activity partial

Adjust the view to match the new heading structure. The URL display section below the heading can be removed for fetch events since the domain is now in the label.

**Files:**
- Modify: `app/views/source_monitor/dashboard/_recent_activity.html.erb`

**Details:**
- The label already renders as the bold heading text (line 14)
- The `url_display` block (lines 24-31) only renders if `event[:url_display].present?`
- Since fetch events no longer set `url_display`, this block won't render for fetches
- Scrape events still use `url_display` so the block remains
- No structural HTML changes needed — just the data changes from the presenter

### Task 3: Update presenter tests

**Files:**
- Modify: `test/lib/source_monitor/dashboard/recent_activity_presenter_test.rb`

**Acceptance:**
- Fetch events have label format "domain — Fetch #N"
- Fetch events no longer include url_display or url_href
- Scrape and item events are unchanged
- Domain extraction failure falls back gracefully
