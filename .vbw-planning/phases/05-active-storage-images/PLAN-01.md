---
phase: 5
plan: "01"
title: images-config-model-rewriter
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used:
  - sm-configure
  - sm-configuration-setting
files_modified:
  - lib/source_monitor/configuration/images_settings.rb
  - lib/source_monitor/configuration.rb
  - lib/source_monitor.rb
  - app/models/source_monitor/item_content.rb
  - lib/source_monitor/images/content_rewriter.rb
  - test/lib/source_monitor/configuration/images_settings_test.rb
  - test/lib/source_monitor/images/content_rewriter_test.rb
  - test/models/source_monitor/item_content_test.rb
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/images_settings_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/content_rewriter_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/item_content_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/configuration/images_settings.rb lib/source_monitor/images/content_rewriter.rb app/models/source_monitor/item_content.rb` exits 0 with no offenses"
    - "`SourceMonitor.config.images` returns an ImagesSettings instance"
    - "`SourceMonitor.config.images.download_to_active_storage` defaults to `false`"
    - "`SourceMonitor.reset_configuration!` resets images settings to defaults"
    - "ContentRewriter.new(html).image_urls returns an array of absolute image URLs found in img tags"
    - "ContentRewriter.new(html).rewrite { |url| new_url } replaces img src attributes with block return values"
    - "ItemContent responds to `images` (has_many_attached) when Active Storage is available"
  artifacts:
    - path: "lib/source_monitor/configuration/images_settings.rb"
      provides: "Image download configuration settings"
      contains: "class ImagesSettings"
    - path: "lib/source_monitor/images/content_rewriter.rb"
      provides: "HTML img tag parser and URL rewriter"
      contains: "class ContentRewriter"
    - path: "test/lib/source_monitor/configuration/images_settings_test.rb"
      provides: "Tests for ImagesSettings defaults, accessors, and reset"
      contains: "class ImagesSettingsTest"
    - path: "test/lib/source_monitor/images/content_rewriter_test.rb"
      provides: "Tests for image URL extraction and HTML rewriting"
      contains: "class ContentRewriterTest"
  key_links:
    - from: "images_settings.rb#download_to_active_storage"
      to: "REQ-24"
      via: "Configurable option defaults to false"
    - from: "content_rewriter.rb#image_urls"
      to: "REQ-24"
      via: "Detects inline images in item content"
    - from: "content_rewriter.rb#rewrite"
      to: "REQ-24"
      via: "Replaces original URLs with Active Storage URLs"
    - from: "item_content.rb#has_many_attached"
      to: "REQ-24"
      via: "Images attached to ItemContent via Active Storage"
---
<objective>
Create the configuration section, model attachment, and HTML content rewriter for downloading inline images to Active Storage. This plan establishes the foundational pieces that the download job (Plan 02) will use. REQ-24.
</objective>
<context>
@lib/source_monitor/configuration.rb -- Main Configuration class. Has 10 sub-sections as attr_readers initialized in constructor. New `images` section follows the same pattern: add `require`, add `attr_reader :images`, initialize `@images = ImagesSettings.new` in constructor. The reset happens via `SourceMonitor.reset_configuration!` which creates a new Configuration instance.

@lib/source_monitor/configuration/scraping_settings.rb -- Good pattern to follow for ImagesSettings. Simple settings class with `attr_accessor`, constants for defaults, `initialize` that calls `reset!`, and `reset!` that sets all defaults. Uses private `normalize_numeric` helper.

@lib/source_monitor/configuration/http_settings.rb -- Another settings pattern. More accessors, same initialize/reset! structure.

@app/models/source_monitor/item_content.rb -- Currently has `belongs_to :item` and `validates :item`. Need to add `has_many_attached :images` which requires Active Storage tables in the database. Since this is a mountable engine, Active Storage tables come from the host app -- they should already exist if the host uses `rails active_storage:install`. The dummy app has `config.active_storage.service` configured but NO Active Storage tables in schema.rb. We need to install them.

@lib/source_monitor.rb -- Module autoload declarations. The new `Images` module should be added here as `module Images; autoload :ContentRewriter, "source_monitor/images/content_rewriter"; end`.

@lib/source_monitor/items/item_creator/content_extractor.rb -- Uses Nokolexbor for HTML parsing. ContentRewriter should also use Nokolexbor (already a gemspec dependency) to parse HTML and find/rewrite img[src] attributes. Nokolexbor is a drop-in Nokogiri replacement with better performance.

**Key design decisions:**
1. ImagesSettings has: `download_to_active_storage` (bool, default false), `max_download_size` (integer bytes, default 10MB), `download_timeout` (integer seconds, default 30), `allowed_content_types` (array, default %w[image/jpeg image/png image/gif image/webp image/svg+xml])
2. ContentRewriter is a pure HTML transformer -- no HTTP, no Active Storage. It takes HTML string, finds img[src], and provides `image_urls` (extraction) and `rewrite` (transformation via block).
3. `has_many_attached :images` on ItemContent is conditional -- only declared when Active Storage is loaded. This prevents errors in host apps that haven't installed Active Storage.
4. For the dummy app, install Active Storage migrations so tests can exercise attachments.
5. ContentRewriter handles relative URLs by requiring a `base_url` parameter for resolution. Feed items always have a source URL that can serve as base.
</context>
<tasks>
<task type="auto">
  <name>create-images-settings</name>
  <files>
    lib/source_monitor/configuration/images_settings.rb
    lib/source_monitor/configuration.rb
    lib/source_monitor.rb
    test/lib/source_monitor/configuration/images_settings_test.rb
  </files>
  <action>
**Create `lib/source_monitor/configuration/images_settings.rb`:**

Follow the ScrapingSettings pattern. The class should have:

```ruby
# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ImagesSettings
      attr_accessor :download_to_active_storage,
        :max_download_size,
        :download_timeout,
        :allowed_content_types

      DEFAULT_MAX_DOWNLOAD_SIZE = 10 * 1024 * 1024  # 10 MB
      DEFAULT_DOWNLOAD_TIMEOUT = 30                   # seconds
      DEFAULT_ALLOWED_CONTENT_TYPES = %w[
        image/jpeg
        image/png
        image/gif
        image/webp
        image/svg+xml
      ].freeze

      def initialize
        reset!
      end

      def reset!
        @download_to_active_storage = false
        @max_download_size = DEFAULT_MAX_DOWNLOAD_SIZE
        @download_timeout = DEFAULT_DOWNLOAD_TIMEOUT
        @allowed_content_types = DEFAULT_ALLOWED_CONTENT_TYPES.dup
      end

      def download_enabled?
        !!download_to_active_storage
      end
    end
  end
end
```

**Modify `lib/source_monitor/configuration.rb`:**

1. Add `require "source_monitor/configuration/images_settings"` after the other require lines.
2. Add `:images` to the `attr_reader` list (after `:scraping`).
3. Add `@images = ImagesSettings.new` in the `initialize` method (after `@scraping`).

**Modify `lib/source_monitor.rb`:**

Add a new `Images` module autoload block after the existing `Items` module:

```ruby
module Images
  autoload :ContentRewriter, "source_monitor/images/content_rewriter"
end
```

**Create `test/lib/source_monitor/configuration/images_settings_test.rb`:**

TDD tests covering:
1. Default values: `download_to_active_storage` is false, `max_download_size` is 10MB, `download_timeout` is 30, `allowed_content_types` includes the 5 types.
2. Accessors work: set each value, read it back.
3. `reset!` restores defaults after changes.
4. `download_enabled?` returns false by default, true when enabled.
5. Integration: `SourceMonitor.config.images` returns ImagesSettings instance.
6. `SourceMonitor.reset_configuration!` resets images settings.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/images_settings_test.rb` and confirm all tests pass. Run `bin/rubocop lib/source_monitor/configuration/images_settings.rb` and confirm no offenses. Verify `SourceMonitor.config.images` returns the settings object in a Rails console or by reading the code.
  </verify>
  <done>
ImagesSettings class created with 4 configurable attributes, sensible defaults, reset! method, and download_enabled? convenience method. Wired into Configuration as `config.images`. Tests pass, RuboCop clean.
  </done>
</task>
<task type="auto">
  <name>install-active-storage-and-add-attachment</name>
  <files>
    app/models/source_monitor/item_content.rb
    test/models/source_monitor/item_content_test.rb
  </files>
  <action>
**Install Active Storage tables in the dummy app:**

Run `cd test/dummy && bin/rails active_storage:install` to generate the Active Storage migration, then run `cd test/dummy && bin/rails db:migrate` to apply it. This adds the `active_storage_blobs`, `active_storage_attachments`, and `active_storage_variant_records` tables to the dummy app's schema.

If the above doesn't work due to engine test setup, manually create a migration in `test/dummy/db/migrate/` that creates the Active Storage tables, matching the standard Rails Active Storage migration content. Then run `bin/rails db:migrate` from the project root.

**Modify `app/models/source_monitor/item_content.rb`:**

Add `has_many_attached :images` conditionally. Since this is a mountable engine and the host app may or may not have Active Storage installed, wrap it:

```ruby
# frozen_string_literal: true

module SourceMonitor
  class ItemContent < ApplicationRecord
    belongs_to :item, class_name: "SourceMonitor::Item", inverse_of: :item_content, touch: true

    validates :item, presence: true

    # Active Storage attachment for downloaded inline images.
    # Only available when the host app has Active Storage installed.
    has_many_attached :images if respond_to?(:has_many_attached)

    SourceMonitor::ModelExtensions.register(self, :item_content)
  end
end
```

Note: `respond_to?(:has_many_attached)` is always true when `activestorage` is loaded (which it is via `rails/all`). If the host app explicitly excludes Active Storage, this gracefully skips. The important thing is that the Active Storage *tables* must exist for the attachment to work at runtime -- but the declaration itself is safe.

Actually, since `rails/all` always loads Active Storage and our gemspec requires `rails >= 8.0.3`, `has_many_attached` will always be available. Use it unconditionally:

```ruby
has_many_attached :images
```

**Create or update `test/models/source_monitor/item_content_test.rb`:**

This file does not currently exist. Create it with:

1. Test that ItemContent belongs_to :item.
2. Test that ItemContent responds to `images` (the attachment).
3. Test that `images` returns an empty collection by default.
4. Test that an image can be attached and retrieved (use `ActiveStorage::Blob.create_and_upload!` with a small test fixture).

Create a small test image fixture: `test/fixtures/files/test_image.png` -- a 1x1 pixel PNG (use the smallest valid PNG binary).

Use `fixture_file_upload` or `io: StringIO.new(...)` pattern for attaching test files.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/item_content_test.rb` and confirm all tests pass. Verify Active Storage tables exist in `test/dummy/db/schema.rb`. Run `bin/rubocop app/models/source_monitor/item_content.rb` and confirm no offenses.
  </verify>
  <done>
Active Storage tables installed in dummy app. ItemContent has `has_many_attached :images`. Tests verify attachment behavior. Schema updated.
  </done>
</task>
<task type="auto">
  <name>create-content-rewriter</name>
  <files>
    lib/source_monitor/images/content_rewriter.rb
    test/lib/source_monitor/images/content_rewriter_test.rb
  </files>
  <action>
**Create `lib/source_monitor/images/content_rewriter.rb`:**

A pure HTML transformer that uses Nokolexbor (already in gemspec) to find and rewrite `<img>` tag `src` attributes.

```ruby
# frozen_string_literal: true

require "nokolexbor"
require "uri"

module SourceMonitor
  module Images
    class ContentRewriter
      attr_reader :html, :base_url

      def initialize(html, base_url: nil)
        @html = html.to_s
        @base_url = base_url
      end

      # Returns an array of absolute image URLs found in <img> tags.
      # Skips data: URIs, blank src, and invalid URLs.
      def image_urls
        return [] if html.blank?

        doc = parse_fragment
        urls = []

        doc.css("img[src]").each do |img|
          url = resolve_url(img["src"])
          urls << url if url && downloadable_url?(url)
        end

        urls.uniq
      end

      # Rewrites <img src="..."> attributes by yielding each original URL
      # to the block and replacing with the block's return value.
      # Returns the rewritten HTML string.
      # If the block returns nil, the original URL is preserved (graceful fallback).
      def rewrite
        return html if html.blank?

        doc = parse_fragment

        doc.css("img[src]").each do |img|
          original_url = resolve_url(img["src"])
          next unless original_url && downloadable_url?(original_url)

          new_url = yield(original_url)
          img["src"] = new_url if new_url.present?
        end

        doc.to_html
      end

      private

      def parse_fragment
        Nokolexbor::DocumentFragment.parse(html)
      end

      def resolve_url(src)
        src = src.to_s.strip
        return nil if src.blank?
        return nil if src.start_with?("data:")

        uri = URI.parse(src)
        if uri.relative? && base_url.present?
          URI.join(base_url, src).to_s
        elsif uri.absolute?
          src
        end
      rescue URI::InvalidURIError
        nil
      end

      def downloadable_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
```

**Create `test/lib/source_monitor/images/content_rewriter_test.rb`:**

Comprehensive tests:

1. **image_urls extraction:**
   - Returns empty array for nil/blank HTML
   - Extracts single img src URL
   - Extracts multiple img src URLs
   - Deduplicates identical URLs
   - Skips data: URIs
   - Skips img tags without src attribute
   - Skips blank src attributes
   - Resolves relative URLs when base_url provided
   - Skips relative URLs when no base_url provided
   - Handles malformed URLs gracefully (returns empty, no exception)

2. **rewrite:**
   - Returns original HTML when no img tags present
   - Returns original HTML when HTML is blank
   - Replaces img src with block return value
   - Preserves original URL when block returns nil (graceful fallback)
   - Handles multiple img tags
   - Preserves other img attributes (alt, class, etc.)
   - Skips data: URIs (does not yield them to block)
   - Handles mixed downloadable and non-downloadable URLs

3. **Edge cases:**
   - HTML with no images returns empty array from image_urls
   - Very large src attributes (truncated URLs) handled gracefully
   - HTML fragments (not full documents)
   - Self-closing img tags (`<img src="..." />`)
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/content_rewriter_test.rb` and confirm all tests pass. Run `bin/rubocop lib/source_monitor/images/content_rewriter.rb` and confirm no offenses.
  </verify>
  <done>
ContentRewriter class created with `image_urls` extraction and `rewrite` transformation methods. Uses Nokolexbor for HTML parsing. Handles relative URLs, data: URIs, and invalid URLs gracefully. Tests cover all scenarios.
  </done>
</task>
<task type="auto">
  <name>integration-test-and-config-test-update</name>
  <files>
    test/lib/source_monitor/configuration_test.rb
    test/lib/source_monitor/configuration/settings_test.rb
  </files>
  <action>
Update existing configuration tests to cover the new `images` section.

**Modify `test/lib/source_monitor/configuration_test.rb`:**

1. Find the test that checks all config sub-sections (likely iterating over attr_readers) and add `:images` to the list.
2. If there's a test for `reset_configuration!`, verify it also resets images settings.

**Modify `test/lib/source_monitor/configuration/settings_test.rb`:**

1. Find where other settings classes are tested (like `assert_kind_of ModelDefinition, @models.item_content`) and add a test that `config.images` is an `ImagesSettings` instance.
2. Add a test that `config.images.download_to_active_storage` defaults to false.

Run the full existing configuration test files to ensure no regressions.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb test/lib/source_monitor/configuration/settings_test.rb` and confirm all tests pass. No new RuboCop offenses.
  </verify>
  <done>
Existing configuration tests updated to cover the new `images` settings section. No regressions in existing tests.
  </done>
</task>
<task type="auto">
  <name>full-plan-01-verification</name>
  <files>
    lib/source_monitor/configuration/images_settings.rb
    lib/source_monitor/configuration.rb
    lib/source_monitor.rb
    app/models/source_monitor/item_content.rb
    lib/source_monitor/images/content_rewriter.rb
  </files>
  <action>
Run the full test suite and linting to confirm no regressions:

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/images_settings_test.rb test/lib/source_monitor/images/content_rewriter_test.rb test/models/source_monitor/item_content_test.rb` -- all new tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration_test.rb test/lib/source_monitor/configuration/settings_test.rb` -- existing config tests pass
3. `bin/rails test` -- full suite passes with 874+ runs and 0 failures
4. `bin/rubocop` -- zero offenses
5. Review the final state:
   - `SourceMonitor.config.images` is accessible and has correct defaults
   - `SourceMonitor::Images::ContentRewriter` is autoloaded
   - `SourceMonitor::ItemContent` has `has_many_attached :images`
   - Active Storage tables exist in dummy app schema
   - All tests are isolated (use `SourceMonitor.reset_configuration!` in setup)

If any test failures or RuboCop offenses are found, fix them before completing.
  </action>
  <verify>
`bin/rails test` exits 0 with 874+ runs, 0 failures. `bin/rubocop` exits 0 with 0 offenses.
  </verify>
  <done>
Plan 01 complete. Configuration, model attachment, and content rewriter are all in place. Full test suite passes. Ready for Plan 02 to build the download job and integration.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/configuration/images_settings_test.rb` -- all tests pass
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/images/content_rewriter_test.rb` -- all tests pass
3. `PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/item_content_test.rb` -- all tests pass
4. `bin/rails test` -- 874+ runs, 0 failures
5. `bin/rubocop` -- 0 offenses
6. `grep -n 'class ImagesSettings' lib/source_monitor/configuration/images_settings.rb` returns a match
7. `grep -n 'attr_reader.*:images' lib/source_monitor/configuration.rb` returns a match
8. `grep -n 'has_many_attached :images' app/models/source_monitor/item_content.rb` returns a match
9. `grep -n 'class ContentRewriter' lib/source_monitor/images/content_rewriter.rb` returns a match
10. `grep -n 'autoload :ContentRewriter' lib/source_monitor.rb` returns a match
</verification>
<success_criteria>
- ImagesSettings class exists with download_to_active_storage (default false), max_download_size, download_timeout, allowed_content_types (REQ-24 config)
- Configuration.images is accessible and resets properly
- ItemContent has has_many_attached :images (REQ-24 attachment)
- Active Storage tables exist in dummy app for testing
- ContentRewriter extracts image URLs from HTML content (REQ-24 detection)
- ContentRewriter rewrites img src attributes via block (REQ-24 URL replacement)
- ContentRewriter preserves original URLs when rewrite block returns nil (REQ-24 graceful fallback)
- All existing tests pass (no regressions)
- RuboCop clean
</success_criteria>
<output>
.vbw-planning/phases/05-active-storage-images/PLAN-01-SUMMARY.md
</output>
