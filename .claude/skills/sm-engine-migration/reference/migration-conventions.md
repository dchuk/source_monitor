# Migration Conventions Reference

## Complete Table Catalog

### sourcemon_sources (core)

Created in: `20241008120000_create_source_monitor_sources.rb`

| Column | Type | Constraints | Default |
|--------|------|------------|---------|
| `name` | string | NOT NULL | - |
| `feed_url` | string | NOT NULL, unique index | - |
| `website_url` | string | - | - |
| `active` | boolean | NOT NULL | `true` |
| `feed_format` | string | - | - |
| `fetch_interval_minutes` | integer | NOT NULL | `360` |
| `next_fetch_at` | datetime | indexed | - |
| `last_fetched_at` | datetime | - | - |
| `last_fetch_duration_ms` | integer | - | - |
| `last_http_status` | integer | - | - |
| `last_error` | text | - | - |
| `last_error_at` | datetime | - | - |
| `etag` | string | - | - |
| `last_modified` | datetime | - | - |
| `failure_count` | integer | NOT NULL | `0` |
| `backoff_until` | datetime | - | - |
| `items_count` | integer | NOT NULL | `0` |
| `scraping_enabled` | boolean | NOT NULL | `false` |
| `auto_scrape` | boolean | NOT NULL | `false` |
| `scrape_settings` | jsonb | NOT NULL | `{}` |
| `scraper_adapter` | string | NOT NULL | `"readability"` |
| `requires_javascript` | boolean | NOT NULL | `false` |
| `custom_headers` | jsonb | NOT NULL | `{}` |
| `items_retention_days` | integer | - | - |
| `max_items` | integer | - | - |
| `metadata` | jsonb | NOT NULL | `{}` |
| `adaptive_fetching_enabled` | boolean | NOT NULL | `true` |
| `type` | string | - | - |
| `fetch_status` | string | CHECK constraint | `"idle"` |
| `fetch_retry_attempt` | integer | - | - |
| `fetch_circuit_opened_at` | datetime | - | - |
| `fetch_circuit_until` | datetime | - | - |
| `rolling_success_rate` | decimal(5,4) | - | - |
| `health_status` | string | NOT NULL, indexed | `"healthy"` |
| `health_status_changed_at` | datetime | - | - |
| `auto_paused_at` | datetime | - | - |
| `auto_paused_until` | datetime | indexed | - |
| `health_auto_pause_threshold` | decimal(5,4) | - | - |
| `feed_content_readability` | string | - | - |

**Indexes:**
- `feed_url` (unique)
- `active`
- `next_fetch_at`
- `created_at`
- `health_status`
- `auto_paused_until`

**CHECK constraints:**
- `check_fetch_status_values`: `fetch_status IN ('idle', 'queued', 'fetching', 'failed', 'invalid')`

---

### sourcemon_items

Created in: `20241008121000_create_source_monitor_items.rb`

| Column | Type | Constraints | Default |
|--------|------|------------|---------|
| `source_id` | reference | NOT NULL, FK | - |
| `guid` | string | NOT NULL, indexed | - |
| `content_fingerprint` | string | indexed | - |
| `title` | string | - | - |
| `url` | string | NOT NULL, indexed | - |
| `canonical_url` | string | - | - |
| `author` | string | - | - |
| `authors` | jsonb | NOT NULL | `[]` |
| `summary` | text | - | - |
| `content` | text | - | - |
| `scraped_at` | datetime | - | - |
| `scrape_status` | string | indexed | - |
| `published_at` | datetime | indexed | - |
| `updated_at_source` | datetime | - | - |
| `categories` | jsonb | NOT NULL | `[]` |
| `tags` | jsonb | NOT NULL | `[]` |
| `keywords` | jsonb | NOT NULL | `[]` |
| `enclosures` | jsonb | NOT NULL | `[]` |
| `media_thumbnail_url` | string | - | - |
| `media_content` | jsonb | NOT NULL | `[]` |
| `language` | string | - | - |
| `copyright` | string | - | - |
| `comments_url` | string | - | - |
| `comments_count` | integer | NOT NULL | `0` |
| `metadata` | jsonb | NOT NULL | `{}` |
| `deleted_at` | datetime | - | - |

**Indexes:**
- `[source_id, guid]` (unique composite)
- `[source_id, content_fingerprint]` (unique composite)
- `[source_id, published_at, created_at]` (named: `index_sourcemon_items_on_source_and_published_at`)
- `guid`
- `content_fingerprint`
- `url`
- `scrape_status`
- `published_at`

---

### sourcemon_fetch_logs

Created in: `20241008122000_create_source_monitor_fetch_logs.rb`

| Column | Type | Constraints | Default |
|--------|------|------------|---------|
| `source_id` | reference | NOT NULL, FK | - |
| `success` | boolean | NOT NULL | `false` |
| `items_created` | integer | NOT NULL | `0` |
| `items_updated` | integer | NOT NULL | `0` |
| `items_failed` | integer | NOT NULL | `0` |
| `started_at` | datetime | NOT NULL, indexed | - |
| `completed_at` | datetime | - | - |
| `duration_ms` | integer | - | - |
| `http_status` | integer | - | - |
| `http_response_headers` | jsonb | NOT NULL | `{}` |
| `error_class` | string | - | - |
| `error_message` | text | - | - |
| `error_backtrace` | text | - | - |
| `feed_size_bytes` | integer | - | - |
| `items_in_feed` | integer | - | - |
| `job_id` | string | indexed | - |
| `metadata` | jsonb | NOT NULL | `{}` |

---

### sourcemon_scrape_logs

Created in: `20241008123000_create_source_monitor_scrape_logs.rb`

References `sourcemon_sources` and `sourcemon_items`.

---

### sourcemon_log_entries (unified log view)

Created in: `20251015100000_create_source_monitor_log_entries.rb`

| Column | Type | Constraints | Default |
|--------|------|------------|---------|
| `loggable_type` | string | NOT NULL (polymorphic) | - |
| `loggable_id` | integer | NOT NULL (polymorphic) | - |
| `source_id` | reference | NOT NULL, FK | - |
| `item_id` | reference | FK (nullable) | - |
| `success` | boolean | NOT NULL | `false` |
| `started_at` | datetime | NOT NULL, indexed | - |
| `completed_at` | datetime | - | - |
| `http_status` | integer | - | - |
| `duration_ms` | integer | - | - |
| `items_created` | integer | - | - |
| `items_updated` | integer | - | - |
| `items_failed` | integer | - | - |
| `scraper_adapter` | string | indexed | - |
| `content_length` | integer | - | - |
| `error_class` | string | - | - |
| `error_message` | text | - | - |

**Indexes:**
- `[loggable_type, loggable_id]` (named: `index_sourcemon_log_entries_on_loggable`)
- `[started_at, id]` (descending, concurrent)
- `[loggable_type, started_at, id]` (descending, concurrent)
- `started_at`
- `success`
- `scraper_adapter`

---

### sourcemon_item_contents

Created in: `20251009090000_create_source_monitor_item_contents.rb`

| Column | Type | Constraints |
|--------|------|------------|
| `item_id` | reference | NOT NULL, FK, unique index |
| `scraped_html` | text | - |
| `scraped_content` | text | - |

---

### sourcemon_health_check_logs

Created in: `20251022100000_create_source_monitor_health_check_logs.rb`

---

### sourcemon_import_sessions

Created in: `20251124090000_create_import_sessions.rb`

Uses dynamic prefix: `:"#{SourceMonitor.table_name_prefix}import_sessions"`

---

### sourcemon_import_histories

Created in: `20251125094500_create_import_histories.rb`

Uses dynamic prefix: `:"#{SourceMonitor.table_name_prefix}import_histories"`

---

## Migration Version History

| Migration | Rails Version | Description |
|-----------|--------------|-------------|
| `20241008120000` | 8.0 | Create sources |
| `20241008121000` | 8.0 | Create items |
| `20241008122000` | 8.0 | Create fetch_logs |
| `20241008123000` | 8.0 | Create scrape_logs |
| `20251008183000` | 8.0 | Change fetch_interval to minutes |
| `20251009090000` | 8.0 | Extract item_contents |
| `20251009103000` | 8.0 | Add feed_content_readability |
| `20251010090000` | 7.1 | Add adaptive_fetching_enabled |
| `20251010123000` | 8.0 | Add deleted_at to items |
| `20251010153000` | 8.0 | Add type to sources (STI) |
| `20251010154500` | 8.0 | Add fetch_status to sources |
| `20251010160000` | 8.0 | Create solid_cable_messages |
| `20251011090000` | 8.0 | Add fetch retry state |
| `20251012090000` | 8.0 | Add health fields |
| `20251012100000` | 8.0 | Optimize indexes |
| `20251014064947` | 8.0 | Add NOT NULL to items |
| `20251014171659` | 8.0 | Add performance indexes |
| `20251014172525` | 8.0 | Add fetch_status CHECK constraint |
| `20251015100000` | 7.1 | Create log_entries |
| `20251022100000` | 8.0 | Create health_check_logs |
| `20251108120116` | 8.0 | Refresh fetch_status constraint |
| `20251124090000` | 8.1 | Create import_sessions |
| `20251124153000` | 8.1 | Add health to import_sessions |
| `20251125094500` | 8.1 | Create import_histories |
| `20260210204022` | 8.1 | Add composite index to log_entries |

## Key Patterns Summary

| Pattern | Convention |
|---------|-----------|
| Table prefix | `sourcemon_` |
| FK to engine table | `foreign_key: { to_table: :sourcemon_<table> }` |
| FK to host table | `foreign_key: true` |
| JSONB hash | `null: false, default: {}` |
| JSONB array | `null: false, default: []` |
| Boolean | `null: false, default: <value>` |
| Counter | `null: false, default: 0` |
| Decimal rate | `precision: 5, scale: 4` |
| Long index name | Use `name:` parameter |
| Zero-downtime index | `disable_ddl_transaction!` + `algorithm: :concurrently` |
| Data backfill | Anonymous AR class + `find_each` |
| Constraint | Raw SQL `execute` with `up`/`down` |
