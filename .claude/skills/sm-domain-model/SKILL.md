---
name: sm-domain-model
description: Provides SourceMonitor engine domain model context. Use when working with engine models, associations, validations, scopes, database schema, or any model-layer code in the source_monitor namespace.
allowed-tools: Read, Glob, Grep
user-invocable: false
---

# SourceMonitor Domain Model

## Overview

SourceMonitor is a Rails 8 mountable engine for RSS/feed monitoring. All models live under the `SourceMonitor::` namespace and inherit from `SourceMonitor::ApplicationRecord`. Tables use a configurable prefix (default: `sourcemon_`).

## Model Graph

```
Source (central entity)
 |-- has_many :items (active only, via scope)
 |-- has_many :all_items (includes soft-deleted)
 |-- has_many :fetch_logs
 |-- has_many :scrape_logs
 |-- has_many :health_check_logs
 |-- has_many :log_entries
 |
 Item
 |-- belongs_to :source (counter_cache: true)
 |-- has_one :item_content (dependent: :destroy, autosave: true)
 |-- has_many :scrape_logs
 |-- has_many :log_entries
 |
 ItemContent
 |-- belongs_to :item (touch: true)
 |
 FetchLog (includes Loggable)
 |-- belongs_to :source
 |-- has_one :log_entry (as: :loggable, polymorphic)
 |
 ScrapeLog (includes Loggable)
 |-- belongs_to :item
 |-- belongs_to :source
 |-- has_one :log_entry (as: :loggable, polymorphic)
 |
 HealthCheckLog (includes Loggable)
 |-- belongs_to :source
 |-- has_one :log_entry (as: :loggable, polymorphic)
 |
 LogEntry (delegated_type :loggable)
 |-- belongs_to :source
 |-- belongs_to :item (optional)
 |-- loggable types: FetchLog, ScrapeLog, HealthCheckLog
 |
 ImportSession (standalone)
 |-- user_id (FK to host app)
 |
 ImportHistory (standalone)
 |-- user_id (FK to host app)
```

## Models Summary

| Model | Table | Purpose |
|-------|-------|---------|
| `Source` | `sourcemon_sources` | Feed source with URL, fetch config, health tracking |
| `Item` | `sourcemon_items` | Individual feed entry/article |
| `ItemContent` | `sourcemon_item_contents` | Scraped HTML/content (split from items for performance) |
| `FetchLog` | `sourcemon_fetch_logs` | Record of each feed fetch attempt |
| `ScrapeLog` | `sourcemon_scrape_logs` | Record of each item scrape attempt |
| `HealthCheckLog` | `sourcemon_health_check_logs` | Record of each health check |
| `LogEntry` | `sourcemon_log_entries` | Unified log view via delegated_type (polymorphic) |
| `ImportSession` | `sourcemon_import_sessions` | OPML import wizard state |
| `ImportHistory` | `sourcemon_import_histories` | Completed import records |

## Key Concerns

### Loggable (`app/models/concerns/source_monitor/loggable.rb`)
Shared by FetchLog, ScrapeLog, HealthCheckLog:
- `attribute :metadata, default: -> { {} }`
- `validates :started_at, presence: true`
- `validates :duration_ms, numericality: { >= 0 }, allow_nil: true`
- Scopes: `recent`, `successful`, `failed`

### Sanitizable (`lib/source_monitor/models/sanitizable.rb`)
String/hash attribute sanitization. Used by Source.

### UrlNormalizable (`lib/source_monitor/models/url_normalizable.rb`)
URL normalization and format validation. Used by Source and Item.

## Source Model Details

### State Values

| Field | Values | Notes |
|-------|--------|-------|
| `fetch_status` | `idle`, `queued`, `fetching`, `failed`, `invalid` | DB CHECK constraint |
| `health_status` | `healthy` (default) | String, extensible |
| `active` | `true`/`false` | Boolean toggle |

### Key Scopes

| Scope | Meaning |
|-------|---------|
| `active` | `WHERE active = true` |
| `failed` | `failure_count > 0 OR last_error IS NOT NULL OR last_error_at IS NOT NULL` |
| `healthy` | `active AND failure_count = 0 AND last_error IS NULL AND last_error_at IS NULL` |
| `due_for_fetch(reference_time:)` | Class method. Active sources where `next_fetch_at IS NULL OR <= reference_time` |

### Validations

| Field | Rules |
|-------|-------|
| `name` | presence |
| `feed_url` | presence, uniqueness (case insensitive) |
| `fetch_interval_minutes` | numericality > 0 |
| `scraper_adapter` | presence |
| `items_retention_days` | integer >= 0, allow nil |
| `max_items` | integer >= 0, allow nil |
| `fetch_status` | inclusion in FETCH_STATUS_VALUES |
| `fetch_retry_attempt` | integer >= 0 |
| `health_auto_pause_threshold` | custom: 0..1 range |

### Notable Methods

- `fetch_interval_hours` / `fetch_interval_hours=` -- convenience accessors converting minutes
- `fetch_circuit_open?` -- circuit breaker check
- `auto_paused?` -- health-based auto-pause check
- `reset_items_counter!` -- recalculate counter cache from active items

## Item Model Details

### Soft Delete Pattern
Items use soft delete via `deleted_at` column (NOT default_scope):
- `scope :active` -- `WHERE deleted_at IS NULL`
- `scope :with_deleted` -- unscopes deleted_at
- `scope :only_deleted` -- `WHERE deleted_at IS NOT NULL`
- `soft_delete!(timestamp:)` -- sets deleted_at, decrements counter cache
- `deleted?` -- checks deleted_at presence

### Key Scopes

| Scope | Meaning |
|-------|---------|
| `active` | `WHERE deleted_at IS NULL` |
| `recent` | Active, ordered by `published_at DESC NULLS LAST, created_at DESC` |
| `published` | Active, `WHERE published_at IS NOT NULL` |
| `pending_scrape` | Active, `WHERE scraped_at IS NULL` |
| `failed_scrape` | Active, `WHERE scrape_status = 'failed'` |

### Validations

| Field | Rules |
|-------|-------|
| `source` | presence |
| `guid` | presence, uniqueness scoped to source_id (case insensitive) |
| `content_fingerprint` | uniqueness scoped to source_id, allow blank |
| `url` | presence |

### Content Delegation
`scraped_html` and `scraped_content` delegate to `ItemContent`. Setting these values auto-creates the ItemContent association. `ensure_feed_content_record` also creates ItemContent for feed word count tracking. ItemContent is only auto-destroyed when both scraped fields are blank AND the item has no feed content.

## LogEntry Delegated Type

LogEntry uses Rails `delegated_type` to unify FetchLog, ScrapeLog, and HealthCheckLog:
- `loggable_type` -- polymorphic type column
- `loggable_id` -- polymorphic ID column
- Helper methods: `fetch?`, `scrape?`, `health_check?`, `log_type`
- After-save sync: each log type calls `Logs::EntrySync.call(self)` to keep LogEntry in sync

## ImportSession Wizard Steps

Ordered steps: `upload` -> `preview` -> `health_check` -> `configure` -> `confirm`

Methods: `next_step`, `previous_step`, `health_stream_name`, `health_check_targets`

## ModelExtensions Registry

All models register via `SourceMonitor::ModelExtensions.register(self, :key)`. This system:
1. Assigns table names using the configured prefix
2. Applies host-app concerns
3. Applies host-app validations
4. Supports `reload!` for configuration changes

## References

- [Model Relationship Graph](reference/model-graph.md) -- Visual model relationships
- [Table Structure](reference/table-structure.md) -- Complete schema with columns, types, indexes
- Source files: `app/models/source_monitor/*.rb`
- Concern: `app/models/concerns/source_monitor/loggable.rb`
- Migrations: `db/migrate/*.rb`
