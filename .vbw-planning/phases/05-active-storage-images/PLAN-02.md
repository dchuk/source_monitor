---
phase: 5
plan: "02"
title: download-job-integration-docs
type: execute
wave: 2
depends_on:
  - "PLAN-01"
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used:
  - sm-configure
  - sm-job
  - sm-engine-test
files_modified:
  - lib/source_monitor/images/downloader.rb
  - app/jobs/source_monitor/download_content_images_job.rb
  - lib/source_monitor/fetching/feed_fetcher/entry_processor.rb
  - lib/source_monitor.rb
  - test/lib/source_monitor/images/downloader_test.rb
  - test/jobs/source_monitor/download_content_images_job_test.rb
  - test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb
  - .claude/skills/sm-configure/SKILL.md
  - .claude/skills/sm-configure/reference/configuration-reference.md
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/downloader_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/download_content_images_job_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/images/downloader.rb app/jobs/source_monitor/download_content_images_job.rb lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` exits 0 with no offenses"
    - "When `config.images.download_to_active_storage` is false (default), no DownloadContentImagesJob is enqueued after item creation"
    - "When `config.images.download_to_active_storage` is true, DownloadContentImagesJob is enqueued for newly created items that have HTML content"
    - "DownloadContentImagesJob downloads images, attaches to ItemContent, and rewrites item.content with Active Storage URLs"
    - "Images that fail to download are left with original URLs in the content (graceful fallback)"
    - "Images larger than max_download_size are skipped and original URL preserved"
    - "Images with disallowed content types are skipped and original URL preserved"
    - "sm-configure skill documents the new config.images section"
  artifacts:
    - path: "lib/source_monitor/images/downloader.rb"
      provides: "Downloads a single image via Faraday, validates size and content type"
      contains: "class Downloader"
    - path: "app/jobs/source_monitor/download_content_images_job.rb"
      provides: "Background job to download and attach content images"
      contains: "class DownloadContentImagesJob"
    - path: "lib/source_monitor/fetching/feed_fetcher/entry_processor.rb"
      provides: "Integration hook to enqueue image download after item creation"
      contains: "enqueue_image_download"
    - path: ".claude/skills/sm-configure/SKILL.md"
      provides: "Updated skill with config.images section documented"
      contains: "config.images"
  key_links:
    - from: "download_content_images_job.rb#perform"
      to: "REQ-24"
      via: "Downloads inline images to Active Storage"
    - from: "entry_processor.rb#enqueue_image_download"
      to: "REQ-24"
      via: "Enqueues download job when config enabled and item has content"
    - from: "downloader.rb"
      to: "REQ-24"
      via: "Validates size and content type before download"
    - from: "sm-configure/SKILL.md"
      to: "REQ-24"
      via: "Configuration documented in sm-configure skill"
---
<objective>
Build the image download job, single-image downloader service, integration hook in the entry processor, and update the sm-configure skill. This plan connects Plan 01's foundational pieces into a working end-to-end image download pipeline. REQ-24.
</objective>
<context>
@lib/source_monitor/images/content_rewriter.rb -- (from Plan 01) Provides `image_urls` to get URLs and `rewrite { |url| new_url }` to transform HTML. The job uses `image_urls` to get the list, downloads each image, attaches to Active Storage, then uses `rewrite` to replace original URLs with Active Storage serving URLs.

@app/models/source_monitor/item_content.rb -- (from Plan 01) Has `has_many_attached :images`. The job attaches downloaded images here via `item_content.images.attach(blob)`.

@lib/source_monitor/configuration/images_settings.rb -- (from Plan 01) Provides `download_enabled?`, `max_download_size`, `download_timeout`, `allowed_content_types`.

@lib/source_monitor/fetching/feed_fetcher/entry_processor.rb -- The integration point. After `ItemCreator.call` returns a created item, if images download is enabled and the item has HTML content in `item.content`, enqueue `DownloadContentImagesJob.perform_later(item.id)`. Only for newly created items (not updates).

@lib/source_monitor/http.rb -- Faraday client factory. The Downloader creates its own Faraday connection: no retry (images are best-effort), short timeout from config, Accept header for images.

@app/jobs/source_monitor/application_job.rb -- Base job class. DownloadContentImagesJob inherits from this. Uses `source_monitor_queue :fetch` (reuse fetch queue since image downloads are I/O-bound like fetches).

@app/jobs/source_monitor/fetch_feed_job.rb -- Pattern to follow for job structure: `discard_on` for deserialization errors, simple `perform` that delegates to service objects.

@test/test_helper.rb -- WebMock disables external HTTP. Image download tests need WebMock stubs. Use `stub_request(:get, url).to_return(body: png_bytes, headers: { "Content-Type" => "image/png" })`.

@.claude/skills/sm-configure/SKILL.md -- Needs a new section for `config.images` with examples.

@app/models/source_monitor/item.rb -- The item model. `item.content` is a text column on `sourcemon_items` storing the feed entry content (HTML). This is where inline images live. The job reads `item.content`, rewrites it, and saves it back. `item_content` (separate table) stores scraped_html/scraped_content from scraping -- that happens later and is separate from feed content.

**Key design decisions:**
1. **Job takes `item_id`** (not item_content_id). The feed content with inline images is in `item.content`. The job reads `item.content`, downloads images, attaches blobs to `item_content.images` (building item_content if needed), and writes the rewritten HTML back to `item.content`.
2. Downloader is a service object that downloads one image: takes URL, returns `{io:, filename:, content_type:}` or nil on failure.
3. The job is idempotent: if `item_content.images.attached?`, it skips re-downloading.
4. The job runs on the fetch queue (I/O-bound work).
5. The job wraps each download in begin/rescue -- one failing image does not block others.
6. After all images are processed, rewrite the HTML once with all successful replacements. Failed images keep their original URLs.
7. Only newly created items trigger image downloads (not updates).
</context>
<tasks>
<task type="auto">
  <name>create-image-downloader</name>
  <files>
    lib/source_monitor/images/downloader.rb
    lib/source_monitor.rb
    test/lib/source_monitor/images/downloader_test.rb
  </files>
  <action>
**Create `lib/source_monitor/images/downloader.rb`:**

A service object that downloads a single image from a URL, validates it, and returns the result.

```ruby
# frozen_string_literal: true

require "faraday"
require "securerandom"

module SourceMonitor
  module Images
    class Downloader
      Result = Struct.new(:io, :filename, :content_type, :byte_size, keyword_init: true)

      attr_reader :url, :settings

      def initialize(url, settings: nil)
        @url = url
        @settings = settings || SourceMonitor.config.images
      end

      # Downloads the image and returns a Result, or nil if download fails
      # or the image does not meet validation criteria.
      def call
        response = fetch_image
        return unless response

        content_type = response.headers["content-type"]&.split(";")&.first&.strip&.downcase
        return unless allowed_content_type?(content_type)

        body = response.body
        return unless body && body.bytesize > 0
        return if body.bytesize > settings.max_download_size

        filename = derive_filename(url, content_type)

        Result.new(
          io: StringIO.new(body),
          filename: filename,
          content_type: content_type,
          byte_size: body.bytesize
        )
      rescue Faraday::Error, URI::InvalidURIError, Timeout::Error => _error
        nil
      end

      private

      def fetch_image
        connection = Faraday.new do |f|
          f.options.timeout = settings.download_timeout
          f.options.open_timeout = [settings.download_timeout / 2, 5].min
          f.headers["User-Agent"] = SourceMonitor.config.http.user_agent || "SourceMonitor/#{SourceMonitor::VERSION}"
          f.headers["Accept"] = "image/*"
          f.adapter Faraday.default_adapter
        end

        response = connection.get(url)
        return response if response.status == 200

        nil
      end

      def allowed_content_type?(content_type)
        return false if content_type.blank?

        settings.allowed_content_types.include?(content_type)
      end

      def derive_filename(image_url, content_type)
        uri = URI.parse(image_url)
        basename = File.basename(uri.path) if uri.path.present?

        if basename.present? && basename.include?(".")
          basename
        else
          ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".bin"
          "image-#{SecureRandom.hex(8)}#{ext}"
        end
      rescue URI::InvalidURIError
        ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".bin"
        "image-#{SecureRandom.hex(8)}#{ext}"
      end
    end
  end
end
```

**Update `lib/source_monitor.rb`:**

Add `autoload :Downloader, "source_monitor/images/downloader"` inside the `module Images` block (added in Plan 01).

**Create `test/lib/source_monitor/images/downloader_test.rb`:**

Use WebMock stubs for all HTTP interactions. Tests:

1. Downloads valid image and returns Result with io, filename, content_type, byte_size
2. Returns nil for HTTP error (404, 500)
3. Returns nil for disallowed content type (e.g., text/html)
4. Returns nil for image exceeding max_download_size
5. Returns nil for empty response body
6. Returns nil for network timeout (stub with `to_timeout`)
7. Derives filename from URL path when available
8. Generates random filename when URL has no extension
9. Uses configured download_timeout
10. Uses configured allowed_content_types
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/downloader_test.rb` and confirm all tests pass. Run `bin/rubocop lib/source_monitor/images/downloader.rb` and confirm no offenses.
  </verify>
  <done>
Downloader service created. Downloads single images, validates content type and size, derives filenames. Returns nil on any failure for graceful fallback. Tests cover all success and failure scenarios.
  </done>
</task>
<task type="auto">
  <name>create-download-job</name>
  <files>
    app/jobs/source_monitor/download_content_images_job.rb
    test/jobs/source_monitor/download_content_images_job_test.rb
  </files>
  <action>
**Create `app/jobs/source_monitor/download_content_images_job.rb`:**

The job takes `item_id`, reads `item.content` for inline images, downloads them, attaches to `item_content.images`, and rewrites `item.content` with Active Storage URLs.

```ruby
# frozen_string_literal: true

module SourceMonitor
  class DownloadContentImagesJob < ApplicationJob
    source_monitor_queue :fetch

    discard_on ActiveJob::DeserializationError

    def perform(item_id)
      item = SourceMonitor::Item.find_by(id: item_id)
      return unless item
      return unless SourceMonitor.config.images.download_enabled?

      html = item.content
      return if html.blank?

      # Build or find item_content for attachment storage
      item_content = item.item_content || item.build_item_content

      # Skip if images already attached (idempotency)
      return if item_content.persisted? && item_content.images.attached?

      base_url = item.url
      rewriter = SourceMonitor::Images::ContentRewriter.new(html, base_url: base_url)
      image_urls = rewriter.image_urls
      return if image_urls.empty?

      # Save item_content first so we can attach blobs to it
      item_content.save! unless item_content.persisted?

      # Download images and build URL mapping
      url_mapping = download_images(item_content, image_urls)
      return if url_mapping.empty?

      # Rewrite HTML with Active Storage URLs
      rewritten_html = rewriter.rewrite do |original_url|
        url_mapping[original_url]
      end

      # Update the item content with rewritten HTML
      item.update!(content: rewritten_html)
    end

    private

    def download_images(item_content, image_urls)
      url_mapping = {}
      settings = SourceMonitor.config.images

      image_urls.each do |image_url|
        result = SourceMonitor::Images::Downloader.new(image_url, settings: settings).call
        next unless result

        blob = ActiveStorage::Blob.create_and_upload!(
          io: result.io,
          filename: result.filename,
          content_type: result.content_type
        )
        item_content.images.attach(blob)

        # Generate a serving URL for the blob
        url_mapping[image_url] = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      rescue StandardError => _error
        # Individual image failure should not block others.
        # Original URL will be preserved (graceful fallback).
        next
      end

      url_mapping
    end
  end
end
```

**Create `test/jobs/source_monitor/download_content_images_job_test.rb`:**

Tests using WebMock stubs and Active Storage test helpers:

1. Downloads images and rewrites item.content HTML when config enabled
2. Skips when config disabled (download_to_active_storage is false)
3. Skips when item not found
4. Skips when item.content is blank
5. Skips when images already attached (idempotency)
6. Skips when no image URLs found in content
7. Gracefully handles individual image download failure (other images still processed)
8. Preserves original URL for failed downloads in rewritten HTML
9. Attaches downloaded images to item_content.images
10. Creates item_content if it does not exist yet

For each test:
- Set up `SourceMonitor.configure { |c| c.images.download_to_active_storage = true }` where needed
- Create a source and item with `content: '<p><img src="https://example.com/photo.jpg"></p>'`
- Stub WebMock for the image URL returning a small PNG binary
- Call `DownloadContentImagesJob.perform_now(item.id)`
- Assert on `item.reload.content` for rewritten URLs and `item.item_content.images.count`
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/download_content_images_job_test.rb` and confirm all tests pass. Run `bin/rubocop app/jobs/source_monitor/download_content_images_job.rb` and confirm no offenses.
  </verify>
  <done>
DownloadContentImagesJob created. Takes item_id, reads item.content, downloads images via Downloader, attaches to item_content via Active Storage, rewrites HTML with blob paths. Idempotent, graceful failure handling. Tests cover all scenarios.
  </done>
</task>
<task type="auto">
  <name>wire-integration-and-update-docs</name>
  <files>
    lib/source_monitor/fetching/feed_fetcher/entry_processor.rb
    test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb
    .claude/skills/sm-configure/SKILL.md
    .claude/skills/sm-configure/reference/configuration-reference.md
  </files>
  <action>
**Modify `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb`:**

Add an integration hook after item creation. In the `process_feed_entries` method, after the `SourceMonitor::Events.after_item_created` call (line 40), add:

```ruby
enqueue_image_download(result.item)
```

This is inside the `if result.created?` block, so it only fires for new items.

Add a private method:

```ruby
def enqueue_image_download(item)
  return unless SourceMonitor.config.images.download_enabled?
  return if item.content.blank?

  SourceMonitor::DownloadContentImagesJob.perform_later(item.id)
rescue StandardError => error
  # Image download enqueue failure must never break feed processing
  if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    Rails.logger.error("[SourceMonitor] Failed to enqueue image download for item #{item.id}: #{error.message}")
  end
end
```

**Create/update entry processor test:**

Check if `test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` exists. If not, create it with a proper test class. Add tests:

1. When images download enabled AND item created with content containing img tags, asserts DownloadContentImagesJob is enqueued with the item's ID
2. When images download disabled (default), asserts no DownloadContentImagesJob enqueued
3. When item is updated (not created), asserts no job enqueued
4. When item.content is blank, asserts no job enqueued
5. When enqueue raises an error, item creation still succeeds (graceful failure)

Use `assert_enqueued_with(job: SourceMonitor::DownloadContentImagesJob, args: [item.id])` and `assert_no_enqueued_jobs(only: SourceMonitor::DownloadContentImagesJob)`.

Test setup needs a source, a mock feed with entries (use Feedjira or a mock object), and configure images download as needed per test.

**Update `.claude/skills/sm-configure/SKILL.md`:**

1. Add `| Images | \`config.images\` | \`ImagesSettings\` |` to the Configuration Sections table.
2. Add a new Quick Example section after "Authentication (Devise)":

```markdown
### Image Downloads (Active Storage)
```ruby
config.images.download_to_active_storage = true
config.images.max_download_size = 5 * 1024 * 1024  # 5 MB
config.images.download_timeout = 15
config.images.allowed_content_types = %w[image/jpeg image/png image/webp]
```

3. Add `| \`lib/source_monitor/configuration/images_settings.rb\` | Image download settings |` to the Key Source Files table.

**Update `.claude/skills/sm-configure/reference/configuration-reference.md`:**

Add a complete "Images Settings" section documenting all ImagesSettings options:

| Setting | Type | Default | Description |
|---|---|---|---|
| download_to_active_storage | Boolean | false | Enable background image downloading |
| max_download_size | Integer | 10485760 (10 MB) | Maximum image file size in bytes |
| download_timeout | Integer | 30 | HTTP timeout for image downloads in seconds |
| allowed_content_types | Array | ["image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml"] | Permitted MIME types |

Include a usage example and note about Active Storage prerequisites (host app must have Active Storage installed).
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` and confirm all tests pass. Run `bin/rubocop lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` and confirm no offenses. Verify `grep -n 'config.images' .claude/skills/sm-configure/SKILL.md` returns matches.
  </verify>
  <done>
Integration hook wired in entry_processor. DownloadContentImagesJob enqueued with item.id for newly created items with HTML content when config enabled. Entry processor tests verify all scenarios. sm-configure skill and reference updated with config.images documentation.
  </done>
</task>
<task type="auto">
  <name>full-plan-02-verification</name>
  <files>
    lib/source_monitor/images/downloader.rb
    app/jobs/source_monitor/download_content_images_job.rb
    lib/source_monitor/fetching/feed_fetcher/entry_processor.rb
    .claude/skills/sm-configure/SKILL.md
  </files>
  <action>
Run the full test suite and linting to confirm no regressions:

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/downloader_test.rb test/jobs/source_monitor/download_content_images_job_test.rb test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` -- all new tests pass
2. `bin/rails test` -- full suite passes with 874+ runs and 0 failures
3. `bin/rubocop` -- zero offenses
4. `bin/brakeman --no-pager` -- zero warnings
5. End-to-end verification:
   - Confirm `config.images.download_to_active_storage = true` enables image downloads
   - Confirm default (false) means no jobs enqueued
   - Confirm the job downloads images, attaches them, and rewrites item.content
   - Confirm failed downloads preserve original URLs
   - Confirm sm-configure skill documents `config.images` section
6. Review all modified files for consistency:
   - Job inherits from ApplicationJob, uses source_monitor_queue :fetch
   - Job takes item_id, reads item.content, rewrites item.content
   - Downloader handles all failure modes gracefully (returns nil)
   - Entry processor integration is wrapped in rescue (never breaks feed processing)
   - ContentRewriter preserves non-image HTML attributes and structure

If any test failures, RuboCop offenses, or Brakeman warnings are found, fix them before completing.
  </action>
  <verify>
`bin/rails test` exits 0 with 874+ runs, 0 failures. `bin/rubocop` exits 0 with 0 offenses. `bin/brakeman --no-pager` exits 0 with 0 warnings. `grep -n 'config.images' .claude/skills/sm-configure/SKILL.md` returns matches.
  </verify>
  <done>
Plan 02 complete. Full image download pipeline is operational: config enables feature, entry processor enqueues job for new items with content, job downloads images via Downloader, attaches to item_content via Active Storage, rewrites item.content with blob URLs. Graceful fallback on all failure modes. Documentation updated. Full test suite passes.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/downloader_test.rb` -- all tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/download_content_images_job_test.rb` -- all tests pass
3. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` -- all tests pass
4. `bin/rails test` -- 874+ runs, 0 failures
5. `bin/rubocop` -- 0 offenses
6. `bin/brakeman --no-pager` -- 0 warnings
7. `grep -n 'class Downloader' lib/source_monitor/images/downloader.rb` returns a match
8. `grep -n 'class DownloadContentImagesJob' app/jobs/source_monitor/download_content_images_job.rb` returns a match
9. `grep -n 'enqueue_image_download' lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` returns a match
10. `grep -n 'config.images' .claude/skills/sm-configure/SKILL.md` returns matches
11. `grep -n 'ImagesSettings' .claude/skills/sm-configure/reference/configuration-reference.md` returns matches
</verification>
<success_criteria>
- Downloader service downloads images, validates size/content-type, returns nil on failure (REQ-24)
- DownloadContentImagesJob takes item_id, orchestrates download/attach/rewrite pipeline on item.content (REQ-24)
- Job is idempotent (skips if images already attached) (REQ-24)
- Failed individual downloads preserve original URLs in content (REQ-24 graceful fallback)
- Entry processor enqueues job only for newly created items when config enabled (REQ-24)
- Entry processor integration never breaks feed processing on failure (REQ-24 graceful)
- Default config (disabled) means zero behavior change to existing pipeline (REQ-24 defaults false)
- sm-configure skill documents config.images section (REQ-24 documentation)
- All existing tests pass (no regressions)
- RuboCop clean, Brakeman clean
</success_criteria>
<output>
.vbw-planning/phases/05-active-storage-images/PLAN-02-SUMMARY.md
</output>
