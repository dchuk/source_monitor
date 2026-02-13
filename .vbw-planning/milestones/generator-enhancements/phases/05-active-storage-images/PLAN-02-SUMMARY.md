---
plan: "02"
phase: 5
title: download-job-integration-docs
status: COMPLETE
requirement: REQ-24
test_runs: 967
test_assertions: 3100
test_failures: 0
rubocop_offenses: 0
brakeman_warnings: 0
commits:
  - hash: 2df856b
    message: "feat(05-02): create-image-downloader"
  - hash: 84e9493
    message: "feat(05-02): create-download-job"
  - hash: e97d2a4
    message: "feat(05-02): wire-integration-and-update-docs"
deviations: none
---

## What Was Built

- **Images::Downloader** -- Service object that downloads a single image via Faraday, validates content type against allowed list, enforces max_download_size, derives filenames from URL or generates random names. Returns nil on any failure for graceful fallback. 11 tests.
- **DownloadContentImagesJob** -- Background job taking item_id. Reads item.content for inline images, downloads via Downloader, attaches blobs to item_content.images via Active Storage, rewrites item.content with blob serving URLs. Idempotent (skips if images already attached). Graceful per-image failure handling. Runs on fetch queue. 10 tests.
- **EntryProcessor integration hook** -- enqueue_image_download called after item creation. Only fires when config.images.download_enabled? is true and item.content is non-blank. Wrapped in rescue so failures never break feed processing. 5 tests.
- **sm-configure skill docs** -- Added config.images section to SKILL.md (table row, quick example, source file entry) and full ImagesSettings documentation to configuration-reference.md.

## Files Modified

- `lib/source_monitor/images/downloader.rb` -- new (Downloader service)
- `lib/source_monitor.rb` -- added Downloader autoload
- `app/jobs/source_monitor/download_content_images_job.rb` -- new (background job)
- `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb` -- added enqueue_image_download hook + private method
- `test/lib/source_monitor/images/downloader_test.rb` -- new (11 tests)
- `test/jobs/source_monitor/download_content_images_job_test.rb` -- new (10 tests)
- `test/lib/source_monitor/fetching/feed_fetcher/entry_processor_test.rb` -- new (5 tests)
- `.claude/skills/sm-configure/SKILL.md` -- added Images row, quick example, source file
- `.claude/skills/sm-configure/reference/configuration-reference.md` -- added ImagesSettings section
