# Entry Processing Pipeline

## Overview

The entry processing pipeline transforms raw feed entries into persisted `Item` records. The pipeline was refactored from a 601-line `ItemCreator` monolith into three focused classes.

```
EntryProcessor (89 lines)
  |
  +-- ItemCreator (174 lines) -- find-or-create orchestrator
        |
        +-- EntryParser (294 lines) -- attribute extraction
        |     +-- MediaExtraction (96 lines) -- media-specific extraction
        |
        +-- ContentExtractor (113 lines) -- readability processing
```

## EntryProcessor

**File:** `lib/source_monitor/fetching/feed_fetcher/entry_processor.rb`

Iterates `feed.entries`, calling `ItemCreator.call` for each. Individual entry failures are caught and counted without stopping the batch.

Returns `EntryProcessingResult` with:
- `created` / `updated` / `failed` counts
- `items` -- all processed Item records
- `created_items` / `updated_items` -- separate lists
- `errors` -- normalized error details for failed entries

## ItemCreator

**File:** `lib/source_monitor/items/item_creator.rb`

Orchestrates finding or creating an Item record for a single feed entry.

### Deduplication Strategy

Items are matched in priority order:

1. **GUID match** (case-insensitive) -- if the entry has a `entry_id`
2. **Content fingerprint** -- SHA256 of `title + url + content`

```ruby
def existing_item_for(attributes, raw_guid_present:)
  if raw_guid_present
    existing = find_item_by_guid(guid)
    return [existing, :guid] if existing
  end
  if fingerprint.present?
    existing = find_item_by_fingerprint(fingerprint)
    return [existing, :fingerprint] if existing
  end
  [nil, nil]
end
```

### Concurrent Duplicate Handling

When `ActiveRecord::RecordNotUnique` is raised during creation, the code falls back to finding and updating the conflicting record:

```ruby
def create_new_item(attributes, raw_guid_present:)
  new_item = source.items.new
  apply_attributes(new_item, attributes)
  new_item.save!
  Result.new(item: new_item, status: :created)
rescue ActiveRecord::RecordNotUnique
  handle_concurrent_duplicate(attributes, raw_guid_present:)
end
```

### Result Struct

```ruby
Result = Struct.new(:item, :status, :matched_by) do
  def created? = status == :created
  def updated? = status == :updated
end
```

## EntryParser

**File:** `lib/source_monitor/items/item_creator/entry_parser.rb`

Extracts all item attributes from a Feedjira entry object. Handles RSS 2.0, Atom, and JSON Feed formats.

### Extracted Fields

| Field | Method | Notes |
|-------|--------|-------|
| `guid` | `extract_guid` | `entry_id` preferred; falls back to `id` if not same as URL |
| `url` | `extract_url` | Tries `url`, `link_nodes` (alternate), `links` |
| `title` | -- | Direct from entry |
| `author` | `extract_author` | Single author string |
| `authors` | `extract_authors` | Aggregates from rss_authors, dc_creators, author_nodes, JSON Feed |
| `summary` | `extract_summary` | Entry summary/description |
| `content` | `extract_content` | Tries `content`, `content_encoded`, `summary` |
| `published_at` | `extract_timestamp` | First of `published`, `updated` |
| `updated_at_source` | `extract_updated_timestamp` | Entry `updated` field |
| `categories` | `extract_categories` | From `categories`, `tags`, JSON Feed tags |
| `tags` | `extract_tags` | Subset of categories |
| `keywords` | `extract_keywords` | From `media_keywords_raw`, `itunes_keywords_raw` |
| `enclosures` | `extract_enclosures` | RSS enclosures, Atom links, JSON attachments |
| `media_thumbnail_url` | `extract_media_thumbnail_url` | Media RSS thumbnails, entry image |
| `media_content` | `extract_media_content` | Media RSS content nodes |
| `language` | `extract_language` | Entry or JSON Feed language |
| `copyright` | `extract_copyright` | Entry or JSON Feed copyright |
| `comments_url` | `extract_comments_url` | RSS comments element |
| `comments_count` | `extract_comments_count` | slash:comments or comments_count |
| `metadata` | `extract_metadata` | Full entry hash under `feedjira_entry` key |
| `content_fingerprint` | `generate_fingerprint` | SHA256 of title+url+content |

### Feed Format Detection

```ruby
def json_entry?
  defined?(Feedjira::Parser::JSONFeedItem) && entry.is_a?(Feedjira::Parser::JSONFeedItem)
end

def atom_entry?
  defined?(Feedjira::Parser::AtomEntry) && entry.is_a?(Feedjira::Parser::AtomEntry)
end
```

### Helper Methods

- `string_or_nil(value)` -- strips and returns nil for blank strings
- `sanitize_string_array(values)` -- deduplicates and compacts
- `split_keywords(value)` -- splits on `,` or `;`
- `safe_integer(value)` -- safe Integer conversion
- `normalize_metadata(value)` -- JSON round-trip for serializable hash

## ContentExtractor

**File:** `lib/source_monitor/items/item_creator/content_extractor.rb`

Processes HTML content through readability parsing when enabled on the source.

### Processing Flow

```
process_feed_content(raw_content, title:)
  -> should_process_feed_content?(raw_content)
     -> source.feed_content_readability_enabled?
     -> raw_content.present?
     -> html_fragment?(raw_content)
  -> wrap_content_for_readability(raw_content, title:)
     -> builds full HTML document with title
  -> ReadabilityParser.new.parse(html:, readability:)
  -> build_feed_content_metadata(result:, raw_content:, processed_content:)
  -> returns [processed_content, metadata]
```

### Guard Conditions

Content processing only runs when:
1. Source has `feed_content_readability_enabled?`
2. Content is present (not blank)
3. Content looks like HTML (`html_fragment?` checks for `<tag` pattern)

### Metadata

Processing metadata is stored under `feed_content_processing` key:
- `strategy` -- always "readability"
- `status` -- parser result status
- `applied` -- whether processed content was used
- `changed` -- whether content differs from raw
- `readability_text_length` -- extracted text length
- `title` -- extracted title

## MediaExtraction

**File:** `lib/source_monitor/items/item_creator/entry_parser/media_extraction.rb`

Mixed into `EntryParser` to handle media-specific fields.

### Enclosure Sources

| Format | Source | Key Fields |
|--------|--------|------------|
| RSS 2.0 | `enclosure_nodes` | url, type, length |
| Atom | `link_nodes` with `rel="enclosure"` | url, type, length |
| JSON Feed | `json["attachments"]` | url, mime_type, size_in_bytes, duration |

### Media Content

From Media RSS `media_content_nodes`: url, type, medium, height, width, file_size, duration, expression.

### Thumbnails

Priority: `media_thumbnail_nodes` first, then `entry.image`.
