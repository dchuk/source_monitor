---
phase: 2
plan: 2
title: item-creator-tests
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0 with zero failures"
    - "Coverage report shows lib/source_monitor/items/item_creator.rb has fewer than 40 uncovered lines (down from 228)"
    - "Running `bin/rails test` exits 0 with no regressions"
  artifacts:
    - "test/lib/source_monitor/items/item_creator_test.rb -- extended with new test methods covering URL extraction, content extraction, concurrent duplicate handling, author/enclosure/media extraction, feed content processing, and utility methods"
  key_links:
    - "REQ-02 substantially satisfied -- ItemCreator branch coverage above 80%"
---

# Plan 02: item-creator-tests

## Objective

Close the coverage gap in `lib/source_monitor/items/item_creator.rb` (currently 228 uncovered lines out of 601). The existing test file covers basic RSS/Atom/JSON creation, fingerprint generation, guid fallback, readability processing, metadata extraction, and guid/fingerprint deduplication. This plan targets the remaining uncovered branches: URL extraction from link_nodes and links arrays, content extraction fallback chain, concurrent duplicate handling (RecordNotUnique), author extraction from multiple sources, enclosure extraction from Atom link_nodes and JSON attachments, media content extraction, language/copyright/comments extraction, keyword splitting, safe_integer edge cases, and the deep_copy utility.

## Context

<context>
@lib/source_monitor/items/item_creator.rb -- 601 lines, item creation with dedup logic
@test/lib/source_monitor/items/item_creator_test.rb -- existing test file with 8 tests
@config/coverage_baseline.json -- lists 228 uncovered lines for item_creator.rb
@test/fixtures/feeds/ -- RSS, Atom, JSON feed fixtures
@test/test_helper.rb -- test infrastructure

**Decomposition rationale:** ItemCreator is the second largest coverage gap. Its uncovered lines cluster into: (1) URL/content/timestamp extraction branches, (2) concurrent duplicate handling, (3) multi-format author/enclosure/media extraction, (4) feed content processing error paths, (5) utility methods. Each task targets a distinct cluster.

**Trade-offs considered:**
- Many branches are triggered by specific Feedjira entry types (AtomEntry, JSONFeedItem). Tests need mock entries or real parsed fixtures to exercise these.
- The concurrent duplicate test (RecordNotUnique) requires careful setup to simulate a race condition without actually racing.
- Testing private methods through the public `call` interface keeps tests realistic, but some deep utility methods (deep_copy, safe_integer, split_keywords) are easier to verify directly.

**What constrains the structure:**
- Must use Feedjira-parsed entries (not plain hashes) to exercise respond_to? checks
- Atom and JSON-specific branches need entries of the correct type
- Tests extend the existing test file
</context>

## Tasks

### Task 1: Test URL extraction fallbacks and content extraction chain

- **name:** test-url-and-content-extraction
- **files:**
  - `lib/source_monitor/items/item_creator.rb` -- (read-only reference)
  - `test/lib/source_monitor/items/item_creator_test.rb`
- **action:** Add tests covering lines 288-310 (extract_url with link_nodes and links arrays), lines 318-336 (extract_content with CONTENT_METHODS fallback chain), and lines 328-342 (extract_timestamp, extract_updated_timestamp). Specifically:
  1. Test extract_url when entry.url is blank but entry.link_nodes has an alternate link with href -- use an Atom entry fixture
  2. Test extract_url when entry.url is blank and link_nodes are empty but entry.links has a URL string
  3. Test extract_url returns nil when no URL source is available (mock entry with no url/link_nodes/links)
  4. Test extract_content tries :content, then :content_encoded, then :summary in order -- create mock entries that respond to different method subsets
  5. Test extract_updated_timestamp returns entry.updated when present, nil otherwise
  Use OpenStruct or Minitest::Mock to create entries with specific respond_to? patterns for edge cases not covered by real feed fixtures.
- **verify:** `bin/rails test test/lib/source_monitor/items/item_creator_test.rb -n /url_extraction|content_extraction|updated_timestamp/i` exits 0
- **done:** Lines 288-310, 318-342 covered.

### Task 2: Test concurrent duplicate handling (RecordNotUnique)

- **name:** test-concurrent-duplicate-handling
- **files:**
  - `test/lib/source_monitor/items/item_creator_test.rb`
- **action:** Add tests covering lines 104-128 (create_new_item rescue RecordNotUnique, handle_concurrent_duplicate, find_conflicting_item). Specifically:
  1. Test that when create_new_item raises ActiveRecord::RecordNotUnique for a guid conflict, the item is found and updated instead
  2. Test that when RecordNotUnique fires for a fingerprint conflict (no raw guid), the item is found by fingerprint and updated
  3. Test that handle_concurrent_duplicate returns a Result with status: :updated and the correct matched_by
  Simulate RecordNotUnique by: (a) creating an item first, (b) stubbing source.items.new to return an item that raises RecordNotUnique on save!, then verifying the fallback path finds and updates the existing item.
- **verify:** `bin/rails test test/lib/source_monitor/items/item_creator_test.rb -n /concurrent_duplicate|record_not_unique/i` exits 0
- **done:** Lines 104-128 covered.

### Task 3: Test multi-format author, enclosure, and media extraction

- **name:** test-author-enclosure-media-extraction
- **files:**
  - `test/lib/source_monitor/items/item_creator_test.rb`
- **action:** Add tests covering lines 348-383 (extract_authors with rss_authors, dc_creators, author_nodes, json authors), lines 416-466 (extract_enclosures from rss enclosure_nodes, atom link_nodes with rel=enclosure, json attachments), and lines 477-499 (extract_media_content). Specifically:
  1. Test extract_authors collects from rss_authors, dc_creators, dc_creator, and author_nodes (name/email/uri) -- deduplicates and compacts
  2. Test extract_enclosures from Atom link_nodes with rel="enclosure" produces entries with source: "atom_link"
  3. Test extract_media_content builds array from media_content_nodes with url, type, medium, height, width, file_size, duration, expression -- compacted
  4. Test extract_media_thumbnail_url falls back from media_thumbnail_nodes to entry.image
  5. Test extract_enclosures skips entries with blank URLs
  Build mock entries using Struct or OpenStruct to simulate the various node types. The JSON-specific paths are already partially tested; focus on Atom and RSS edge cases.
- **verify:** `bin/rails test test/lib/source_monitor/items/item_creator_test.rb -n /authors|enclosure|media_content|media_thumbnail/i` exits 0
- **done:** Lines 348-383, 416-466, 477-499 covered.

### Task 4: Test feed content processing error path and readability edge cases

- **name:** test-feed-content-processing-errors
- **files:**
  - `test/lib/source_monitor/items/item_creator_test.rb`
- **action:** Add tests covering lines 137-158 (process_feed_content error rescue), lines 160-165 (should_process_feed_content?), lines 187-208 (default_feed_readability_options, build_feed_content_metadata), and lines 210-231 (html_fragment?, deep_copy). Specifically:
  1. Test that when readability parser raises an error, the item is created with raw content and error metadata (lines 148-157): metadata has "status"=>"failed", "error_class", "error_message"
  2. Test should_process_feed_content? returns false when content is blank or when content has no HTML tags (html_fragment? returns false)
  3. Test deep_copy handles Hash, Array, and objects that support deep_dup, plus TypeError rescue
  4. Test build_feed_content_metadata includes readability_text_length and title when present
  5. Test html_fragment? returns true for `<p>text</p>` and false for plain text
  Stub the parser class to raise for the error path test. Use source with feed_content_readability_enabled: true.
- **verify:** `bin/rails test test/lib/source_monitor/items/item_creator_test.rb -n /processing_error|html_fragment|deep_copy|readability_metadata/i` exits 0
- **done:** Lines 137-165, 187-231 covered.

### Task 5: Test utility methods: safe_integer, split_keywords, string_or_nil, normalize_metadata, extract_guid edge cases

- **name:** test-utility-methods
- **files:**
  - `test/lib/source_monitor/items/item_creator_test.rb`
- **action:** Add tests covering lines 501-534 (extract_language, extract_copyright, extract_comments_url, extract_comments_count), lines 536-543 (extract_metadata with normalize_metadata), lines 555-597 (string_or_nil, sanitize_string_array, split_keywords, safe_integer, json_entry?, atom_entry?, normalize_metadata). Specifically:
  1. Test safe_integer returns nil for nil, returns Integer for Integer, parses string "42", returns nil for non-numeric string (lines 574-584)
  2. Test split_keywords splits on commas and semicolons, strips whitespace, removes blank entries (lines 565-572)
  3. Test extract_guid returns nil when entry_id equals URL (dedup logic at line 283-285)
  4. Test extract_language from json_entry? path (line 506-507) and from entry.language (line 502-503)
  5. Test normalize_metadata returns empty hash for unparseable values (JSON roundtrip at lines 594-597)
  6. Test extract_comments_count tries slash_comments_raw then comments_count (lines 529-533)
  Use mock entries with targeted respond_to? patterns. For json_entry? and atom_entry? tests, use actual Feedjira-parsed entries from fixtures.
- **verify:** `bin/rails test test/lib/source_monitor/items/item_creator_test.rb -n /safe_integer|split_keywords|extract_guid_edge|language|copyright|normalize_metadata|comments_count/i` exits 0
- **done:** Lines 501-597 covered.

## Verification

1. `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0
2. `COVERAGE=1 bin/rails test test/lib/source_monitor/items/item_creator_test.rb` shows item_creator.rb with >80% branch coverage
3. `bin/rails test` exits 0 (no regressions)

## Success Criteria

- [ ] ItemCreator coverage drops from 228 uncovered lines to fewer than 40
- [ ] URL extraction fallback branches tested
- [ ] Concurrent duplicate handling tested
- [ ] Multi-format author/enclosure/media extraction tested
- [ ] Feed content processing error paths tested
- [ ] All utility methods tested
- [ ] REQ-02 substantially satisfied
