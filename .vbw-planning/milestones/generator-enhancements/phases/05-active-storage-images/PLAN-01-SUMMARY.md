# PLAN-01 Summary: images-config-model-rewriter

## Status: COMPLETE

## What Was Built

### Task 1: Create ImagesSettings config class
- Added `ImagesSettings` class with `download_to_active_storage` (default false), `max_download_size` (10MB), `download_timeout` (30s), `allowed_content_types` (5 image MIME types)
- Wired into `Configuration` as `config.images` attr_reader, initialized in constructor
- Added `require` to configuration.rb and `Images` module autoload to lib/source_monitor.rb
- 15 tests covering defaults, accessors, reset!, download_enabled?, integration with SourceMonitor.config

### Task 2: Install Active Storage and add attachment
- Created Active Storage migration in dummy app (`test/dummy/db/migrate/20260212000000_create_active_storage_tables.rb`)
- Active Storage tables (blobs, attachments, variant_records) added to dummy app schema
- Added `has_many_attached :images` to `ItemContent` model
- Created 1x1 PNG test fixture at `test/fixtures/files/test_image.png`
- 6 tests covering belongs_to, validates presence, images attachment, empty collection, single/multiple attach

### Task 3: Create ContentRewriter class
- Added `ContentRewriter` class in `lib/source_monitor/images/content_rewriter.rb` using Nokolexbor
- `image_urls` method extracts absolute image URLs from `<img>` tags, skipping data: URIs and invalid URLs
- `rewrite` method yields each downloadable URL to a block and replaces src with return value; preserves original on nil return
- Handles relative URL resolution via `base_url` parameter, whitespace in src, self-closing tags
- 27 tests covering extraction, rewriting, and edge cases

### Task 4: Update existing configuration tests
- Added 4 images settings tests to `configuration_test.rb` (accessible, defaults, configure block, reset)
- Added `ImagesSettingsInSettingsTest` class to `settings_test.rb` with 4 tests (defaults, reset, download_enabled?, type check)

### Task 5: Full verification
- All 941 tests pass (0 failures, 0 errors)
- RuboCop: 384 files, 0 offenses (12 array bracket spacing issues auto-fixed)

## Files Modified
- `lib/source_monitor/configuration/images_settings.rb` (new -- ImagesSettings class)
- `lib/source_monitor/configuration.rb` (added images_settings require, attr_reader, initialization)
- `lib/source_monitor.rb` (added Images module autoload)
- `app/models/source_monitor/item_content.rb` (added has_many_attached :images)
- `lib/source_monitor/images/content_rewriter.rb` (new -- ContentRewriter class)
- `test/lib/source_monitor/configuration/images_settings_test.rb` (new -- 15 tests)
- `test/models/source_monitor/item_content_test.rb` (new -- 6 tests)
- `test/lib/source_monitor/images/content_rewriter_test.rb` (new -- 27 tests)
- `test/lib/source_monitor/configuration_test.rb` (added 4 images tests)
- `test/lib/source_monitor/configuration/settings_test.rb` (added 4 images tests)
- `test/dummy/db/migrate/20260212000000_create_active_storage_tables.rb` (new -- Active Storage migration)
- `test/dummy/db/schema.rb` (updated with Active Storage tables)
- `test/fixtures/files/test_image.png` (new -- 1x1 PNG fixture)

## Commits
- `884a3f6` feat(05-01): create-images-settings
- `52f4291` feat(05-01): install-active-storage-and-add-attachment
- `e199999` feat(05-01): create-content-rewriter
- `3954cb1` test(05-01): integration-test-and-config-test-update
- `05705a8` style(05-01): fix array bracket spacing in content_rewriter_test

## Requirements Satisfied
- REQ-24 config: ImagesSettings with download_to_active_storage toggle (default false), size/timeout/content-type limits
- REQ-24 attachment: ItemContent has has_many_attached :images via Active Storage
- REQ-24 detection: ContentRewriter.image_urls extracts downloadable image URLs from HTML content
- REQ-24 URL replacement: ContentRewriter.rewrite replaces img src attributes via block
- REQ-24 graceful fallback: ContentRewriter preserves original URLs when rewrite block returns nil

## Verification Results
- `bin/rails test`: 941 runs, 3045 assertions, 0 failures, 0 errors
- `bin/rubocop`: 384 files inspected, 0 offenses

## Deviations
None. All tasks executed as specified in the plan.
