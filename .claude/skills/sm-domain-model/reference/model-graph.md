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
  Scraped
  content
```

## Association Details

### Source -> Item
- `has_many :items` -- Only active (non-deleted) items via `-> { active }` scope
- `has_many :all_items` -- All items including soft-deleted
- `dependent: :destroy` on all_items
- Counter cache: `items_count` on Source (tracks active items)

### Item -> ItemContent
- `has_one :item_content` -- Lazy-created when scraped content is assigned
- `dependent: :destroy, autosave: true`
- `touch: true` on the belongs_to side
- Content is auto-destroyed when both `scraped_html` and `scraped_content` become blank

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

The counter is decremented manually during `soft_delete!` and can be recalculated via `reset_items_counter!`.
