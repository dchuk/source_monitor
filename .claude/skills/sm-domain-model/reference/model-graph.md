# SourceMonitor Model Relationship Graph

## Core Feed Monitoring

```
                          SourceMonitor::Source
                          =====================
                          Central entity: a feed URL to monitor
                          Table: sourcemon_sources
                                    |
          +-----------+-------------+-------------+-----------+------------+
          |           |             |             |           |            |
     has_many    has_many      has_many      has_many    has_many     has_many
     :items      :all_items   :fetch_logs   :scrape_    :health_     :log_entries
     (active)    (all)                       logs       check_logs
          |           |             |             |           |            |
          v           v             v             v           v            v
     SourceMonitor::Item       FetchLog      ScrapeLog   HealthCheckLog  LogEntry
     ===================      ========      =========   ==============  ========
     Feed entry/article        Fetch         Scrape       Health        Unified
     Table: sourcemon_items    attempt       attempt      check         log view
          |                    record        record       record
          |
     +----+----+
     |         |
   has_one   has_many
   :item_    :scrape_logs
   content
     |         |
     v         v
  ItemContent  ScrapeLog
  ===========  (also belongs_to :source)
  Feed + scraped
  word counts
```

## Association Details

### Source -> Item
- `has_many :items` -- Only active (non-deleted) items via `-> { active }` scope
- `has_many :all_items` -- All items including soft-deleted
- `dependent: :destroy` on all_items
- Counter cache: `items_count` on Source (tracks active items)

### Item -> ItemContent
- `has_one :item_content` -- Created when item has feed content (via `ensure_feed_content_record`) or when scraped content is assigned
- `dependent: :destroy, autosave: true`
- `touch: true` on the belongs_to side
- Stores `feed_word_count` (from `item.content`) and `scraped_word_count` (from `scraped_content`)
- Content is auto-destroyed only when both scraped fields are blank AND item has no feed content

### Source -> FetchLog
- `has_many :fetch_logs, dependent: :destroy`
- Each FetchLog records one feed fetch attempt with HTTP details, item counts, timing

### Source -> ScrapeLog (and Item -> ScrapeLog)
- ScrapeLog has dual parents: `belongs_to :source` AND `belongs_to :item`
- Validates that `item.source_id == source_id` (source must match item's source)
- Records one content scrape attempt per item

### Source -> HealthCheckLog
- `has_many :health_check_logs, dependent: :destroy`
- Records health check results for the source

### LogEntry (Delegated Type)
- Polymorphic unified view of all log types
- `delegated_type :loggable, types: [FetchLog, ScrapeLog, HealthCheckLog]`
- `belongs_to :source` (always present)
- `belongs_to :item` (optional, present for scrape logs)
- Synced via `Logs::EntrySync.call()` after each log save

## Import Subsystem (Standalone)

```
ImportSession                     ImportHistory
=============                     =============
OPML import wizard state          Completed import record
Table: sourcemon_import_sessions  Table: sourcemon_import_histories

Fields:                           Fields:
- user_id (FK -> users)           - user_id (FK -> users)
- opml_file_metadata (jsonb)      - imported_sources (jsonb)
- parsed_sources (jsonb)          - failed_sources (jsonb)
- selected_source_ids (jsonb)     - skipped_duplicates (jsonb)
- bulk_settings (jsonb)           - bulk_settings (jsonb)
- current_step (string)           - started_at / completed_at
- health_checks_active (bool)
- health_check_target_ids (jsonb)
```

These models reference the host app's `users` table and are NOT directly associated with Source/Item models.

## Polymorphic Patterns

### Delegated Type (LogEntry)
LogEntry uses `delegated_type` (not STI) for the unified log view:
```ruby
# LogEntry
delegated_type :loggable, types: %w[
  SourceMonitor::FetchLog
  SourceMonitor::ScrapeLog
  SourceMonitor::HealthCheckLog
]
```

### STI Column on Source
Source has a `type` column for potential STI subclassing but it is not actively used with subclasses currently.

## Counter Caches

| Parent | Column | Child | Notes |
|--------|--------|-------|-------|
| Source | `items_count` | Item | Only counts active (non-deleted) items |

The counter is decremented manually during `soft_delete!` and **incremented** during `restore!`. Both operations update `items_count` atomically. Use `reset_items_counter!` to recalculate from scratch if the counter drifts.

## Model Methods (v0.12.0+)

### Source.enable_scraping!(ids)

Bulk-enables scraping for a list of source IDs:

```ruby
Source.enable_scraping!([1, 2, 3])
# Sets scraping_enabled = true for each source in the list
```

Use case: enabling scraping on a filtered set of sources from the dashboard or a rake task.

### Item#restore!

Reverses a soft delete. Symmetric counterpart to `soft_delete!`:

```ruby
item.restore!
# Clears deleted_at, increments source.items_count
```

After `restore!`, the item re-enters the `:items` (active) association and the source counter cache reflects the change.

### health_status Validation

As of v0.12.0, `health_status` is validated against the four permitted values. Assigning an unrecognized value raises a validation error:

```ruby
source.health_status = "healthy"  # invalid -- was removed in 0.11.0
source.valid?                      # => false
source.errors[:health_status]      # => ["is not included in the list"]
```

Permitted values: `"working"`, `"declining"`, `"improving"`, `"failing"`.

## Schema Notes (v0.12.0)

- **Composite indexes on log tables:** `sourcemon_fetch_logs`, `sourcemon_scrape_logs`, and `sourcemon_health_check_logs` now have composite indexes on `(source_id, created_at)` to improve log query performance on busy sources.
- **health_status default alignment:** The `health_status` column default on `sourcemon_sources` was updated to `"working"` (previously `"healthy"`, a removed value) to match the four-value enum added in v0.11.0.
