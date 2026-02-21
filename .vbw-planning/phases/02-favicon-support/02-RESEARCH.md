# Phase 2: Favicon Support — Research

Researched: 2026-02-20

## Findings

### Source Model Structure
- Location: `app/models/source_monitor/source.rb`
- Existing columns: name, feed_url, website_url, active, feed_format, fetch_interval_hours, next_fetch_at, last_fetched_at, last_error, failure_count, metadata (JSONB), custom_headers (JSONB), scrape_settings (JSONB)
- No existing Active Storage attachments on Source model
- ItemContent model uses `has_many_attached :images if defined?(ActiveStorage)` guard pattern (proven)
- ModelExtensions.register called at line 53 for host app extensibility

### FeedFetcher Pipeline (Success Flow)
- `FeedFetcher#call` → `perform_fetch` → `handle_response`
- On HTTP 200: `handle_success` calls entry_processor.process_feed_entries then source_updater.update_source_for_success
- source_updater.update_source_for_success (lines 14-40 of source_updater.rb) is the hooking point for favicon triggering
- Source metadata JSONB can track favicon_last_attempted_at for cooldown

### Active Storage Patterns
- DownloadContentImagesJob pattern: `ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:)` then `model.images.attach(blob)`
- ImagesSettings defines DEFAULT_ALLOWED_CONTENT_TYPES including image/svg+xml

### HTTP Module
- `SourceMonitor::HTTP.client()` provides Faraday with retry (4x), gzip, redirect following (5 max), SSL, custom headers
- Can directly use for favicon HTML fetch and image download

### Source Views
- Row template: `app/views/source_monitor/sources/_row.html.erb` (lines 24-102)
- Shows source.name with link, feed_url, health/fetch status badges
- No current favicon display — simple `<div class="font-medium text-slate-900">` wrapper for name
- Tailwind CSS utility classes throughout

### Job Patterns
- All inherit from ApplicationJob, use `source_monitor_queue :role`
- DownloadContentImagesJob: `perform(item_id)` with model lookup and early returns
- `discard_on ActiveJob::DeserializationError` for resilience

### Configuration DSL
- Settings pattern: class with attr_accessors, initialize calls reset!, constants for defaults
- ImagesSettings attributes: download_to_active_storage, max_download_size, download_timeout, allowed_content_types
- Access via: `SourceMonitor.config.images`

## Relevant Patterns

1. **Conditional feature guard**: `has_one_attached :favicon if defined?(ActiveStorage)` + job early return
2. **Blob attachment**: create_and_upload! then model.attachment.attach(blob) (from DownloadContentImagesJob)
3. **HTTP client reuse**: `SourceMonitor::HTTP.client(headers: ...)` for all network requests
4. **Metadata JSONB state**: favicon_last_attempted_at for cooldown tracking (no schema change needed)
5. **Settings class pattern**: FaviconsSettings following ImagesSettings template
6. **Nokolexbor**: Already in gemspec as Nokogiri-compatible HTML parser

## Risks

1. **Network timeouts in cascade**: Favicon discovery adds HTTP requests. Mitigate with aggressive timeout (5s) and async job (not blocking feed fetch)
2. **SVG rasterization complexity**: Rails Active Storage has content-type quirks with SVG. Mitigate by storing raw + optional rasterization
3. **Storage quota**: Large favicons (512x512+). Mitigate with max_download_size (1MB) and dimension validation
4. **Cooldown state in metadata**: Could be cleared if source metadata is modified. Acceptable risk for MVP

## Recommendations

1. Create `FaviconsSettings` configuration class with: enabled, fetch_timeout (5s), max_download_size (1MB), retry_cooldown_days (7), allowed_content_types
2. Use `has_one_attached :favicon` (not has_many) with ActiveStorage guard
3. Create `FetchFaviconJob` on `:fetch` queue, triggered from source_updater after successful fetch when favicon blank
4. Create `Favicons::Discoverer` module with cascade: /favicon.ico → HTML parsing (Nokogiri, prefer largest) → Google Favicon API
5. Store cooldown state in metadata JSONB (no migration needed for source table)
6. View: conditional favicon display with initials fallback placeholder
