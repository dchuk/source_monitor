---
phase: "06"
plan: "04"
title: "Mocking Standardization & Test Conventions Guide"
status: complete
wave: 1
commits: 3
tests_before: 1569
tests_after: 1569
test_failures: 0
rubocop_offenses: 0
---

## What Was Built

- TEST_CONVENTIONS.md covering mocking approach (Minitest .stub primary), test naming (imperative mood), job testing patterns, WebMock stub conventions, time travel, test isolation, and factory helpers
- Advisory lock test refactored with convention-compliant comments explaining why Class.new is used over .stub
- FeedFetcherTestHelper expanded with four reusable WebMock stub helpers: stub_feed_request, stub_feed_timeout, stub_feed_not_found, stub_feed_connection_failed

## Commits

- `eea34ac` docs(06-04): create TEST_CONVENTIONS.md
- `29e817f` refactor(06-04): add mocking convention comments to advisory_lock_test
- `5edfb8f` feat(06-04): add reusable WebMock stub helpers to FeedFetcherTestHelper

## Tasks Completed

- Create TEST_CONVENTIONS.md (175 lines, under 200 limit)
- Refactor advisory_lock_test mocking (Class.new retained with justification comment)
- Consolidate feed_fetcher_test_helper stubs (4 new helpers added)

## Files Modified

- `test/TEST_CONVENTIONS.md` (created)
- `test/lib/source_monitor/fetching/advisory_lock_test.rb` (modified)
- `test/lib/source_monitor/fetching/feed_fetcher_test_helper.rb` (modified)

## Deviations

None.
