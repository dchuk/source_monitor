---
phase: "06"
plan: "02"
title: System Test Base Class & VCR Documentation
status: complete
---

## What Was Built

Enhanced ApplicationSystemTestCase with centralized Capybara wait configuration (default_max_wait_time = 5), setup/teardown lifecycle hooks (config reset, Jobs::Visibility management), screenshot-on-failure, and stale tmp file cleanup. Extracted shared helpers (purge_solid_queue_tables, seed_queue_activity, apply_turbo_stream_messages, parse_turbo_streams, assert_item_order) into a SystemTestHelpers module. Refactored dashboard_test.rb and items_test.rb to use the shared base and helpers, removing ~130 lines of duplicated code. Created VCR cassette maintenance documentation.

## Commits

- `eb8937c` feat(06-02): enhance ApplicationSystemTestCase with Capybara config and lifecycle hooks
- `54617b8` feat(06-02): create SystemTestHelpers module with shared system test methods
- `f412e50` refactor(06-02): refactor system tests to use shared base class and helpers
- `5ff36a3` docs(06-02): create VCR cassette maintenance guide

## Tasks Completed

- Enhance ApplicationSystemTestCase
- Create SystemTestHelpers module
- Refactor system tests to use shared base
- Create VCR cassette maintenance guide

## Files Modified

- `test/application_system_test_case.rb` -- added Capybara config, setup/teardown, screenshot-on-failure, tmp cleanup
- `test/support/system_test_helpers.rb` -- new module with 5 extracted helpers
- `test/system/dashboard_test.rb` -- removed duplicated helpers and setup/teardown logic
- `test/system/items_test.rb` -- removed local assert_item_order, removed redundant wait: 5
- `test/VCR_GUIDE.md` -- new VCR cassette naming, recording, and maintenance documentation

## Deviations

Pre-existing failures (DEVN-05) in system tests unrelated to this plan:
- `ItemsTest#test_manually_scraping_an_item_updates_content_and_records_a_log` -- badge shows "Scraped" before "Pending" can be asserted (timing issue with inline jobs)
- `SourcesTest` -- 4 errors and 1 failure related to health menu selectors and table sorting (unmodified files)
- `DropdownFallbackTest` -- 404 on `/test_support/dropdown_without_dependency` route
- `MissionControlTest` -- error in unmodified file
