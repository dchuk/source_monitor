# SourceMonitor Table Structure

All tables use a configurable prefix (default: `sourcemon_`).

## sourcemon_sources

Core feed source configuration and state.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| name | string | NO | | Feed display name |
| feed_url | string | NO | | RSS/Atom feed URL |
| website_url | string | YES | | Source website URL |
| active | boolean | NO | true | Enable/disable toggle |
| feed_format | string | YES | | Detected format (rss, atom, etc.) |
| fetch_interval_minutes | integer | NO | 360 | Fetch frequency (was hours, migrated) |
| next_fetch_at | datetime | YES | | Next scheduled fetch time |
| last_fetched_at | datetime | YES | | Last fetch attempt time |
| last_fetch_started_at | datetime | YES | | When current fetch started |
| last_fetch_duration_ms | integer | YES | | Last fetch duration |
| last_http_status | integer | YES | | Last HTTP response status |
| last_error | text | YES | | Last error message |
| last_error_at | datetime | YES | | Last error timestamp |
| etag | string | YES | | HTTP ETag for conditional requests |
| last_modified | datetime | YES | | HTTP Last-Modified for conditional requests |
| failure_count | integer | NO | 0 | Consecutive failure count |
| backoff_until | datetime | YES | | Backoff expiry time |
| items_count | integer | NO | 0 | Counter cache (active items) |
| scraping_enabled | boolean | NO | false | Content scraping toggle |
| auto_scrape | boolean | NO | false | Auto-scrape new items |
| scrape_settings | jsonb | NO | {} | Scraper configuration |
| scraper_adapter | string | NO | "readability" | Scraper adapter name |
| requires_javascript | boolean | NO | false | JS rendering needed |
| custom_headers | jsonb | NO | {} | Custom HTTP headers |
| items_retention_days | integer | YES | | Item retention period |
| max_items | integer | YES | | Maximum items to keep |
| metadata | jsonb | NO | {} | Extensible metadata (last_feed_signature, etc.) |
| type | string | YES | | STI column (unused currently) |
| fetch_status | string | NO | "idle" | idle/queued/fetching/failed/invalid |
| fetch_retry_attempt | integer | NO | 0 | Current retry attempt number |
| fetch_circuit_opened_at | datetime | YES | | Circuit breaker open time |
| fetch_circuit_until | datetime | YES | | Circuit breaker expiry |
| adaptive_fetching_enabled | boolean | NO | true | Adaptive interval toggle |
| feed_content_readability_enabled | boolean | NO | false | Process feed content through readability |
| rolling_success_rate | decimal(5,4) | YES | | Rolling success rate (0.0-1.0) |
| health_status | string | NO | "healthy" | Health status string |
| health_status_changed_at | datetime | YES | | Last health status change |
| auto_paused_at | datetime | YES | | When source was auto-paused |
| auto_paused_until | datetime | YES | | Auto-pause expiry |
| health_auto_pause_threshold | decimal(5,4) | YES | | Custom pause threshold (0.0-1.0) |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| unique | feed_url | |
| btree | active | |
| btree | next_fetch_at | |
| btree | fetch_status | |
| btree | type | |
| btree | created_at | |
| btree | health_status | |
| btree | auto_paused_until | |
| btree | fetch_retry_attempt | |
| btree | fetch_circuit_until | |
| partial | [active, next_fetch_at] | WHERE active = true |
| partial | failure_count | WHERE failure_count > 0 |

### Constraints
| Constraint | Expression |
|------------|------------|
| check_fetch_status_values | `fetch_status IN ('idle','queued','fetching','failed','invalid')` |

---

## sourcemon_items

Individual feed entries/articles.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| source_id | bigint | NO | | FK -> sourcemon_sources |
| guid | string | NO | | Unique entry identifier |
| content_fingerprint | string | YES | | SHA256 content hash |
| title | string | YES | | Entry title |
| url | string | NO | | Entry URL |
| canonical_url | string | YES | | Canonical URL |
| author | string | YES | | Primary author |
| authors | jsonb | NO | [] | All authors |
| summary | text | YES | | Entry summary/excerpt |
| content | text | YES | | Full entry content |
| scraped_at | datetime | YES | | When content was scraped |
| scrape_status | string | YES | | Scrape result status |
| published_at | datetime | YES | | Publication date |
| updated_at_source | datetime | YES | | Source's last-modified date |
| categories | jsonb | NO | [] | Category tags |
| tags | jsonb | NO | [] | Tags |
| keywords | jsonb | NO | [] | Keywords |
| enclosures | jsonb | NO | [] | Media enclosures |
| media_thumbnail_url | string | YES | | Thumbnail URL |
| media_content | jsonb | NO | [] | Media content entries |
| language | string | YES | | Content language |
| copyright | string | YES | | Copyright notice |
| comments_url | string | YES | | Comments page URL |
| comments_count | integer | NO | 0 | Number of comments |
| metadata | jsonb | NO | {} | Extensible metadata |
| deleted_at | datetime | YES | | Soft delete timestamp |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | guid | |
| btree | content_fingerprint | |
| btree | url | |
| btree | scrape_status | |
| btree | published_at | |
| btree | deleted_at | |
| unique | [source_id, guid] | |
| unique | [source_id, content_fingerprint] | |
| btree | [source_id, published_at, created_at] | |
| btree | [source_id, created_at] | |

---

## sourcemon_item_contents

Scraped content storage (split from items table for performance).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| item_id | bigint | NO | | FK -> sourcemon_items, unique |
| scraped_html | text | YES | | Raw scraped HTML |
| scraped_content | text | YES | | Processed text content |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| unique | item_id | |

---

## sourcemon_fetch_logs

Records of feed fetch attempts.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| source_id | bigint | NO | | FK -> sourcemon_sources |
| success | boolean | NO | false | Fetch succeeded |
| items_created | integer | NO | 0 | New items from this fetch |
| items_updated | integer | NO | 0 | Updated items |
| items_failed | integer | NO | 0 | Failed items |
| started_at | datetime | NO | | Fetch start time |
| completed_at | datetime | YES | | Fetch end time |
| duration_ms | integer | YES | | Duration in milliseconds |
| http_status | integer | YES | | HTTP response status |
| http_response_headers | jsonb | NO | {} | Response headers |
| error_class | string | YES | | Error class name |
| error_message | text | YES | | Error message |
| error_backtrace | text | YES | | Error backtrace (first 20 lines) |
| feed_size_bytes | integer | YES | | Feed body size |
| items_in_feed | integer | YES | | Total entries in feed |
| job_id | string | YES | | ActiveJob ID |
| metadata | jsonb | NO | {} | Extra metadata (parser, errors) |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | success | |
| btree | started_at | |
| btree | job_id | |
| btree | created_at | |

---

## sourcemon_scrape_logs

Records of item content scrape attempts.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| item_id | bigint | NO | | FK -> sourcemon_items |
| source_id | bigint | NO | | FK -> sourcemon_sources |
| success | boolean | NO | false | Scrape succeeded |
| started_at | datetime | NO | | Scrape start time |
| completed_at | datetime | YES | | Scrape end time |
| duration_ms | integer | YES | | Duration in milliseconds |
| http_status | integer | YES | | HTTP response status |
| scraper_adapter | string | YES | | Adapter used |
| content_length | integer | YES | | Scraped content length |
| error_class | string | YES | | Error class name |
| error_message | text | YES | | Error message |
| metadata | jsonb | NO | {} | Extra metadata |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | success | |
| btree | created_at | |
| btree | started_at | |

---

## sourcemon_health_check_logs

Records of source health checks.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| source_id | bigint | NO | | FK -> sourcemon_sources |
| success | boolean | NO | false | Check succeeded |
| started_at | datetime | NO | | Check start time |
| completed_at | datetime | YES | | Check end time |
| duration_ms | integer | YES | | Duration in milliseconds |
| http_status | integer | YES | | HTTP response status |
| http_response_headers | jsonb | NO | {} | Response headers |
| error_class | string | YES | | Error class name |
| error_message | text | YES | | Error message |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | started_at | |
| btree | success | |

---

## sourcemon_log_entries

Unified log view using delegated_type polymorphism.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| loggable_type | string | NO | | Polymorphic type |
| loggable_id | bigint | NO | | Polymorphic ID |
| source_id | bigint | NO | | FK -> sourcemon_sources |
| item_id | bigint | YES | | FK -> sourcemon_items (scrape logs) |
| success | boolean | NO | false | Operation succeeded |
| started_at | datetime | NO | | Operation start time |
| completed_at | datetime | YES | | Operation end time |
| http_status | integer | YES | | HTTP response status |
| duration_ms | integer | YES | | Duration in milliseconds |
| items_created | integer | YES | | New items (fetch logs) |
| items_updated | integer | YES | | Updated items (fetch logs) |
| items_failed | integer | YES | | Failed items (fetch logs) |
| scraper_adapter | string | YES | | Adapter (scrape logs) |
| content_length | integer | YES | | Content length (scrape logs) |
| error_class | string | YES | | Error class name |
| error_message | text | YES | | Error message |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | [loggable_type, loggable_id] | |
| btree | started_at | |
| btree | success | |
| btree | scraper_adapter | |
| btree | [started_at DESC, id DESC] | |
| btree | [loggable_type, started_at DESC, id DESC] | |

---

## sourcemon_import_sessions

OPML import wizard state tracking.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| user_id | bigint | NO | | FK -> users (host app) |
| opml_file_metadata | jsonb | NO | {} | Uploaded file info |
| parsed_sources | jsonb | NO | [] | Parsed OPML entries |
| selected_source_ids | jsonb | NO | [] | User-selected sources |
| bulk_settings | jsonb | NO | {} | Bulk import settings |
| current_step | string | NO | | Current wizard step |
| health_checks_active | boolean | NO | false | Health checks running |
| health_check_target_ids | jsonb | NO | [] | Sources being checked |
| health_check_started_at | datetime | YES | | Health check start |
| health_check_completed_at | datetime | YES | | Health check end |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | current_step | |
| btree | health_checks_active | |

---

## sourcemon_import_histories

Completed import records.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | bigint | NO | auto | PK |
| user_id | bigint | NO | | FK -> users (host app) |
| imported_sources | jsonb | NO | [] | Successfully imported |
| failed_sources | jsonb | NO | [] | Failed imports |
| skipped_duplicates | jsonb | NO | [] | Skipped duplicates |
| bulk_settings | jsonb | NO | {} | Settings used |
| started_at | datetime | YES | | Import start time |
| completed_at | datetime | YES | | Import end time |
| created_at | datetime | NO | | |
| updated_at | datetime | NO | | |

### Indexes
| Index | Columns | Options |
|-------|---------|---------|
| btree | created_at | |

---

## Foreign Key Summary

| From Table | Column | To Table |
|------------|--------|----------|
| sourcemon_items | source_id | sourcemon_sources |
| sourcemon_item_contents | item_id | sourcemon_items |
| sourcemon_fetch_logs | source_id | sourcemon_sources |
| sourcemon_scrape_logs | item_id | sourcemon_items |
| sourcemon_scrape_logs | source_id | sourcemon_sources |
| sourcemon_health_check_logs | source_id | sourcemon_sources |
| sourcemon_log_entries | source_id | sourcemon_sources |
| sourcemon_log_entries | item_id | sourcemon_items |
| sourcemon_import_sessions | user_id | users |
| sourcemon_import_histories | user_id | users |
