---
phase: 2
plan_count: 3
status: complete
started: 2026-02-20
completed: 2026-02-20
total_tests: 7
passed: 7
skipped: 0
issues: 0
---

# Phase 2: Favicon Support -- UAT

## P01-T1: Favicon configuration accessible with correct defaults

**Plan:** 01 -- Favicon Infrastructure: Config, Model, Job, and Discovery

Run `bin/rails console` and execute:
```ruby
SourceMonitor.config.favicons.enabled?
SourceMonitor.config.favicons.fetch_timeout
SourceMonitor.config.favicons.max_download_size
SourceMonitor.config.favicons.retry_cooldown_days
SourceMonitor.config.favicons.allowed_content_types
```

**Expected:** enabled? returns true, fetch_timeout=5, max_download_size=1048576, retry_cooldown_days=7, allowed_content_types includes image/x-icon and image/png.

**Result:** PASS (automated) -- `bin/rails runner` confirmed: enabled?=true, fetch_timeout=5, max_download_size=1048576, retry_cooldown_days=7, allowed_content_types includes image/x-icon and image/png.

---

## P01-T2: Host app without Active Storage doesn't crash

**Plan:** 01 -- Favicon Infrastructure: Config, Model, Job, and Discovery

Verify that the Source model loads and the initializer template includes the new Favicons section. Open `lib/generators/source_monitor/install/templates/source_monitor.rb.tt` and confirm there is a commented `# ---- Favicons ----` section with configuration examples.

**Expected:** The initializer template contains a Favicons section with commented-out `config.favicons.*` settings. The `enabled?` method documents it returns false when Active Storage is not defined.

**Result:** PASS (automated) -- Initializer template contains `# ---- Favicons ----` section with commented config examples. `favicons_settings.rb:38` confirms `enabled?` checks `!!enabled && !!defined?(ActiveStorage)`.

---

## P02-T1: Sources index shows colored initials placeholders

**Plan:** 02 -- Favicon View Display with Fallback Placeholder

Start `bin/dev`, navigate to the sources index page. Look at each source row in the list.

**Expected:** Each source has a small colored circle (24px) showing the first letter of its name next to the source name. Different sources should have different colored circles. The colors should be consistent (same source always gets the same color).

**Result:** PASS -- Colored initials circles visible on sources index. Different sources show different colors.

---

## P02-T2: Source detail page shows larger placeholder next to heading

**Plan:** 02 -- Favicon View Display with Fallback Placeholder

Click into any source's detail/show page.

**Expected:** A larger colored initials placeholder (40px) appears next to the source name heading (h1). The initial letter and color match what was shown in the index row for that source.

**Result:** PASS

---

## P03-T1: Creating a source with website_url triggers favicon fetch

**Plan:** 03 -- Favicon Fetch Triggers: Source Creation and Feed Success

Create a new source via the UI with a `website_url` field filled in (e.g., `https://github.com`). After saving, check the Solid Queue dashboard or logs for a FaviconFetchJob being enqueued.

**Expected:** A FaviconFetchJob is enqueued for the newly created source. The source page loads without errors regardless of whether the job has completed.

**Result:** PASS (automated) -- `sources_controller_favicon_test.rb` (5 tests, 14 assertions, 0 failures) confirms: create with website_url enqueues FaviconFetchJob; create without website_url does not; create with favicons disabled does not; create failure does not.

---

## P03-T2: Favicon replaces placeholder after job completes

**Plan:** 03 -- Favicon Fetch Triggers: Source Creation and Feed Success

After the FaviconFetchJob runs for a source (wait a few seconds or trigger via console with `SourceMonitor::FaviconFetchJob.perform_now(source.id)`), refresh the source show page and the sources index.

**Expected:** The colored initials placeholder is replaced by the actual favicon image. The image is properly sized (24px on index, 40px on show) and does not distort.

**Result:** PASS -- Two bugs found and fixed during UAT: (1) `url_for(source.favicon)` raised ArgumentError in engine context; fixed with `Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)`. (2) `.ico` favicons rendered as invisible/transparent; fixed by reordering discovery cascade to prefer HTML `<link>` tags (PNG) over `/favicon.ico`. After fixes, Airbnb favicon (PNG from miro.medium.com) renders correctly at 24px on index and 40px on show page. Commit: adc9f74.

---

## P03-T3: OPML import triggers favicon fetches for imported sources

**Plan:** 03 -- Favicon Fetch Triggers: Source Creation and Feed Success

Import an OPML file containing sources with website URLs. After the import completes, check the job queue for FaviconFetchJob entries.

**Expected:** One FaviconFetchJob is enqueued per imported source that has a website_url. Sources without website_url do not get a job enqueued. The import flow itself completes without errors.

**Result:** PASS (automated) -- `import_opml_favicon_test.rb` (3 tests, 14 assertions, 0 failures) confirms: OPML import enqueues FaviconFetchJob per source with website_url; skips sources without website_url; skips when favicons disabled.
