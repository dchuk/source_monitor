---
phase: 4
plan: 2
title: item-creator-extraction
wave: 1
depends_on: []
skills_used: []
cross_phase_deps:
  - "Phase 3 Plan 01 -- FeedFetcher extraction pattern (sub-module directory with require from main file)"
  - "Phase 2 Plan 02 -- ItemCreator tests exist at test/lib/source_monitor/items/item_creator_test.rb"
must_haves:
  truths:
    - "Running `wc -l lib/source_monitor/items/item_creator.rb` shows fewer than 300 lines"
    - "Running `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0 with zero failures"
    - "Running `bin/rails test` exits 0 with 760+ runs and 0 failures"
    - "Running `ruby -c lib/source_monitor/items/item_creator.rb` exits 0 (valid syntax)"
    - "Running `ruby -c lib/source_monitor/items/item_creator/content_extractor.rb` exits 0"
    - "Running `ruby -c lib/source_monitor/items/item_creator/entry_parser.rb` exits 0"
    - "Running `bin/rubocop lib/source_monitor/items/item_creator.rb lib/source_monitor/items/item_creator/` exits 0"
  artifacts:
    - "lib/source_monitor/items/item_creator/entry_parser.rb -- extracted entry field parsing (guid, url, authors, enclosures, media, metadata, etc.)"
    - "lib/source_monitor/items/item_creator/content_extractor.rb -- extracted feed content processing and readability"
    - "lib/source_monitor/items/item_creator.rb -- slimmed to orchestrator under 300 lines"
  key_links:
    - "Phase 4 success criterion #1 -- all service objects follow established conventions"
    - "No single file exceeds 300 lines (extends Phase 3 criterion)"
    - "Public API unchanged -- ItemCreator.call(source:, entry:) returns Result struct"
---

# Plan 02: item-creator-extraction

## Objective

Extract `lib/source_monitor/items/item_creator.rb` (601 lines, 50+ methods) into focused sub-modules following the exact same extraction pattern used by `FeedFetcher` in Phase 3 (sub-module directory with require from main file). The public API (`ItemCreator.call(source:, entry:)` returning a `Result` struct) must remain unchanged. All existing ItemCreator tests must continue to pass without modification.

## Context

<context>
@lib/source_monitor/items/item_creator.rb -- 601 lines with 50+ methods. The largest file in the codebase after Phase 3 refactoring. Contains three clearly separable responsibility clusters:

**Cluster 1: Core attribute building (build_attributes, ~90 lines)**
The `build_attributes` method (lines 233-271) assembles all item attributes by calling field extraction methods. This is the main orchestration method and should stay in the main file.

**Cluster 2: Field extraction from feed entries (~300 lines)**
Methods that extract specific fields from Feedjira entry objects:
- `extract_guid` (lines 273-287)
- `extract_url` (lines 288-311)
- `extract_summary` (lines 312-317)
- `extract_content` (lines 318-327)
- `extract_timestamp` (lines 328-337)
- `extract_updated_timestamp` (lines 338-343)
- `extract_author` (lines 344-347)
- `extract_authors` (lines 348-384)
- `extract_categories` (lines 385-394)
- `extract_tags` (lines 395-408)
- `extract_keywords` (lines 409-415)
- `extract_enclosures` (lines 416-467)
- `extract_media_thumbnail_url` (lines 468-476)
- `extract_media_content` (lines 477-500)
- `extract_language` (lines 501-512)
- `extract_copyright` (lines 513-524)
- `extract_comments_url` (lines 525-528)
- `extract_comments_count` (lines 529-535)
- `extract_metadata` (lines 536-544)
Plus utility methods: `generate_fingerprint`, `string_or_nil`, `sanitize_string_array`, `split_keywords`, `safe_integer`, `json_entry?`, `atom_entry?`, `normalize_metadata` (lines 545-601)

**Cluster 3: Feed content processing (~75 lines)**
Methods for processing raw feed content through readability:
- `process_feed_content` (lines 137-158)
- `should_process_feed_content?` (lines 160-165)
- `feed_content_parser_class` (lines 167-170)
- `wrap_content_for_readability` (lines 171-186)
- `default_feed_readability_options` (lines 187-193)
- `build_feed_content_metadata` (lines 194-209)
- `html_fragment?` (lines 210-213)
- `deep_copy` (lines 214-231)

**What stays in the main file (~200 lines):**
- Result struct definition
- Constants (FINGERPRINT_SEPARATOR, CONTENT_METHODS, etc.)
- Constructor, `self.call`, `call` method
- `existing_item_for`, `find_item_by_guid`, `find_item_by_fingerprint`
- `instrument_duplicate`, `update_existing_item`, `create_new_item`
- `handle_concurrent_duplicate`, `find_conflicting_item`, `apply_attributes`
- `build_attributes` (calls into extracted modules)
- Lazy accessor methods for sub-modules

@lib/source_monitor/fetching/feed_fetcher.rb -- 285 lines. The extraction pattern to follow: main file requires sub-modules, uses lazy accessors (e.g., `def source_updater; @source_updater ||= SourceUpdater.new(...); end`), delegates method calls.
@lib/source_monitor/fetching/feed_fetcher/source_updater.rb -- Example sub-module: namespaced under FeedFetcher, constructor receives dependencies.
@lib/source_monitor/fetching/feed_fetcher/entry_processor.rb -- Another example sub-module.
@test/lib/source_monitor/items/item_creator_test.rb -- Existing tests. Must pass without modification.
</context>

## Tasks

### Task 1: Extract EntryParser module

- **name:** extract-entry-parser
- **files:**
  - `lib/source_monitor/items/item_creator/entry_parser.rb` (new)
  - `lib/source_monitor/items/item_creator.rb`
- **action:** Create `lib/source_monitor/items/item_creator/entry_parser.rb` containing a `SourceMonitor::Items::ItemCreator::EntryParser` class. Move these methods from item_creator.rb into the new class:
  - `extract_guid` -- entry GUID extraction with JSON/Atom fallbacks
  - `extract_url` -- URL extraction with canonical/alternate link resolution
  - `extract_summary` -- summary text extraction
  - `extract_content` -- content extraction from multiple methods
  - `extract_timestamp` -- published_at extraction
  - `extract_updated_timestamp` -- updated_at extraction
  - `extract_author` -- single author extraction
  - `extract_authors` -- multi-author extraction with JSON parsing
  - `extract_categories` -- category extraction
  - `extract_tags` -- tag extraction
  - `extract_keywords` -- keyword extraction with separator splitting
  - `extract_enclosures` -- enclosure/attachment extraction
  - `extract_media_thumbnail_url` -- media thumbnail extraction
  - `extract_media_content` -- media content metadata extraction
  - `extract_language` -- language detection
  - `extract_copyright` -- copyright extraction
  - `extract_comments_url` -- comments link extraction
  - `extract_comments_count` -- comments count extraction
  - `extract_metadata` -- raw metadata extraction
  - `generate_fingerprint` -- content fingerprint generation
  - Utility methods: `string_or_nil`, `sanitize_string_array`, `split_keywords`, `safe_integer`, `json_entry?`, `atom_entry?`, `normalize_metadata`

  The EntryParser constructor takes `source:` and `entry:` (same as ItemCreator). It exposes a single public method `parse` that returns a hash of all extracted attributes (what `build_attributes` currently assembles). Add `require_relative "item_creator/entry_parser"` at the top of item_creator.rb. In ItemCreator, create an `entry_parser` lazy accessor and delegate the field extraction to it.
- **verify:** `ruby -c lib/source_monitor/items/item_creator/entry_parser.rb` exits 0 AND `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0 with zero failures
- **done:** EntryParser extracted with all field extraction methods. Tests pass unchanged.

### Task 2: Extract ContentExtractor module

- **name:** extract-content-extractor
- **files:**
  - `lib/source_monitor/items/item_creator/content_extractor.rb` (new)
  - `lib/source_monitor/items/item_creator.rb`
- **action:** Create `lib/source_monitor/items/item_creator/content_extractor.rb` containing a `SourceMonitor::Items::ItemCreator::ContentExtractor` class. Move these methods:
  - `process_feed_content` -- orchestrates content processing through readability
  - `should_process_feed_content?` -- determines if content should be processed
  - `feed_content_parser_class` -- resolves the parser class
  - `wrap_content_for_readability` -- wraps raw content with HTML structure for parsing
  - `default_feed_readability_options` -- default options for readability
  - `build_feed_content_metadata` -- builds metadata about processing results
  - `html_fragment?` -- checks if content is HTML
  - `deep_copy` -- deep copies complex values

  The ContentExtractor constructor takes `source:`. It exposes `process_feed_content(raw_content, title:)` as the primary public method. Add `require_relative "item_creator/content_extractor"` at the top of item_creator.rb. In ItemCreator, create a `content_extractor` lazy accessor. The EntryParser from Task 1 should call `content_extractor.process_feed_content(...)` instead of the local method -- wire this through the constructor or pass as a dependency.
- **verify:** `ruby -c lib/source_monitor/items/item_creator/content_extractor.rb` exits 0 AND `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0
- **done:** ContentExtractor extracted. Feed content processing isolated. Tests pass unchanged.

### Task 3: Slim main ItemCreator and wire modules

- **name:** slim-item-creator-and-wire
- **files:**
  - `lib/source_monitor/items/item_creator.rb`
- **action:** After Tasks 1-2, the main item_creator.rb should contain:
  - Require statements for 2 sub-modules
  - Existing requires (digest, json, cgi, etc.)
  - Result struct definition
  - Constants (FINGERPRINT_SEPARATOR, CONTENT_METHODS, TIMESTAMP_METHODS, etc.)
  - Constructor and `self.call`
  - `call` method (find or create)
  - `existing_item_for`, `find_item_by_guid`, `find_item_by_fingerprint`
  - `instrument_duplicate`, `update_existing_item`, `create_new_item`
  - `handle_concurrent_duplicate`, `find_conflicting_item`, `apply_attributes`
  - `build_attributes` (now delegates to entry_parser.parse)
  - Lazy accessor methods for entry_parser and content_extractor

  Clean up any dead code, orphaned requires, or duplicated constants. Ensure the main file is under 300 lines. Run RuboCop on all modified/new files.
- **verify:** `wc -l lib/source_monitor/items/item_creator.rb` shows fewer than 300 lines AND `bin/rubocop lib/source_monitor/items/item_creator.rb lib/source_monitor/items/item_creator/` exits 0 AND `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0
- **done:** ItemCreator main file under 300 lines. All sub-modules wired. RuboCop clean.

### Task 4: Full test suite regression check

- **name:** full-regression-check
- **files:** (no new modifications -- verification only)
- **action:** Run the complete test suite to verify no regressions from the extraction. Check that: (a) all 760+ tests pass, (b) no new RuboCop violations, (c) ItemCreator public API (`ItemCreator.call(source:, entry:)` returning `Result` struct) works identically to before the extraction. Verify by inspecting any tests that use ItemCreator in other test files (e.g., feed_fetcher_test.rb, import_opml_job tests) to confirm they still pass.
- **verify:** `bin/rails test` exits 0 with 760+ runs and 0 failures AND `bin/rubocop -f simple` shows `no offenses detected`
- **done:** Full suite passes. Zero RuboCop violations. No regressions from extraction.

## Verification

1. `wc -l lib/source_monitor/items/item_creator.rb` shows fewer than 300 lines
2. `wc -l lib/source_monitor/items/item_creator/entry_parser.rb lib/source_monitor/items/item_creator/content_extractor.rb` shows both exist
3. `bin/rails test test/lib/source_monitor/items/item_creator_test.rb` exits 0 with zero failures
4. `bin/rails test` exits 0 with 760+ runs and 0 failures
5. `bin/rubocop lib/source_monitor/items/` exits 0

## Success Criteria

- [ ] ItemCreator main file under 300 lines
- [ ] Two sub-modules created: entry_parser.rb, content_extractor.rb
- [ ] Public API unchanged -- ItemCreator.call(source:, entry:) returns Result struct
- [ ] All existing tests pass without modification
- [ ] Full test suite passes (760+ runs, 0 failures)
- [ ] RuboCop passes on all modified/new files
- [ ] No file in app/ or lib/ exceeds 300 lines (extends Phase 3 success criterion)
