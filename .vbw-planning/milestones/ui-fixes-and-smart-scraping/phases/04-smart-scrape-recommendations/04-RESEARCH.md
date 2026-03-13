# Phase 04: Smart Scrape Recommendations — Research

## Findings

### 1. Source Model Structure
**File:** `app/models/source_monitor/source.rb`

- **Key attributes:** `scraping_enabled` (boolean), `scraper_adapter` (string, validates presence), `scrape_settings` (JSONB), `min_scrape_interval` (optional)
- **Existing scopes & methods:**
  - `active` scope for filtering
  - `due_for_fetch` class method for scheduling
  - `avg_word_count` method (lines 134-139) — currently computes average of **scraped** word counts only
  - Ransacker columns for `avg_feed_words` and `avg_scraped_words` (lines 83-99) — query `ItemContent` for feed/scraped word counts by source
- **Counter caches:** `items_count` auto-maintained via has_many association

### 2. Configuration DSL
**File:** `lib/source_monitor/configuration.rb`

- `SourceMonitor.configure { |c| c.attr = value }` pattern
- `@scraping = ScrapingSettings.new` already initialized
- **ScrapingSettings** has: `max_in_flight_per_source`, `max_bulk_batch_size`, `min_scrape_interval`
- Pattern: `attr_accessor` + `DEFAULT_*` constant + `reset!` method

### 3. Dashboard Structure
**Files:** `app/controllers/source_monitor/dashboard_controller.rb`, `lib/source_monitor/dashboard/queries.rb`

- Dashboard renders via `queries.stats`, `queries.recent_activity`, `queries.quick_actions`, `queries.job_metrics`, `queries.upcoming_fetch_schedule`
- **StatsQuery** returns: `{ total_sources, active_sources, failed_sources, total_items, fetches_today, health_distribution }`
- Widget structure: bordered card with header + divider + list/content

### 4. Sources Index Structure
**Files:** `app/controllers/source_monitor/sources_controller.rb` + view

- Uses **Ransack** for search (`searchable_with` mixin)
- Index action: builds `@q` (Ransack query), computes `@avg_feed_word_counts` and `@avg_scraped_word_counts` as hashes (source_id -> avg)
- Row partial renders with `item_activity_rates`, word count maps
- Row has dropdown menu with View/Edit/Delete actions

### 5. Scraping Pipeline
**Files:** `app/jobs/source_monitor/scrape_item_job.rb`, `lib/source_monitor/scraping/bulk_source_scraper.rb`, `lib/source_monitor/scraping/item_scraper.rb`

- **ScrapeItemJob:** Checks `source.scraping_enabled?`, respects `min_scrape_interval`, calls `ItemScraper`
- **BulkSourceScraper:** Selections: `:current`, `:unscraped`, `:all`. Returns Result struct with: `status`, `selection`, `attempted_count`, `enqueued_count`, `already_enqueued_count`, `failure_count`, `failure_details`, `messages`, `rate_limited`
- **ItemScraper:** Resolves adapter via `AdapterResolver`, calls adapter, persists result

### 6. Item Model & Word Count Computation
**Files:** `app/models/source_monitor/item.rb`, `app/models/source_monitor/item_content.rb`

- Item has `has_one :item_content` (autosave: true)
- ItemContent stores `feed_word_count` and `scraped_word_count` (computed)
- Computation: `feed_word_count` from `item.content`, `scraped_word_count` from `item_content.scraped_content`
- Both computed in `before_save` hook

### 7. Analytics Patterns
**File:** `lib/source_monitor/analytics/sources_index_metrics.rb`

- Takes `base_scope`, `result_scope`, `search_params`
- Computes distribution via `SourceFetchIntervalDistribution`
- Results cached via private attributes
- Used in controller index action to populate display data

### 8. Existing Bulk Action Patterns
**File:** `app/controllers/source_monitor/source_bulk_scrapes_controller.rb`

- Single source bulk scrape: `POST /sources/:source_id/bulk_scrape`
- Params: `{ bulk_scrape: { selection: :current/:unscraped/:all } }`
- Responds with Turbo Stream, uses `SourceTurboResponses` mixin

### 9. Routes
**File:** `config/routes.rb`

- Sources resources with nested `resource :bulk_scrape, only: :create`
- Dashboard: `get "/dashboard"` -> `dashboard#index`

### 10. Test Patterns
- Uses `create_source!` factory, mocks services, tests Turbo Stream responses
- Asserts turbo-stream tags with `dom_id(source, :row)`

## Relevant Patterns

1. **Configuration**: Add `scrape_recommendation_threshold` to `ScrapingSettings` with DEFAULT constant + reset
2. **Dashboard widget**: Follow existing card pattern (header + divider + content)
3. **Word count filtering**: Leverage existing Ransack ransackers (`avg_feed_words`)
4. **Bulk enablement**: Follow bulk scrape pattern with Turbo Stream responder
5. **Presenter pattern**: Source row uses locals for computed data
6. **Analytics class**: Follow `SourcesIndexMetrics` pattern for recommendation computation

## Risks

1. **Word count accuracy**: `avg_feed_words` Ransacker joins ItemContent — need all items to have content records
2. **Bulk action feedback**: BulkSourceScraper can rate-limit — UI must handle partial enqueuing
3. **Modal confirmation UX**: Needs Stimulus controller for toggle
4. **Test-first scrape page**: New route/view — must follow CRUD-everything pattern

## Recommendations

1. Add to ScrapingSettings with default 200 words
2. Add `Source.scrape_candidates` scope using avg_feed_words threshold
3. Dashboard widget: new card between stats and recent activity
4. Index badge: warning indicator on rows where avg_feed_words < threshold
5. Bulk selection: Stimulus checkboxes + new controller action
6. Test-first: New route `POST /sources/:id/test_scrape` -> comparison page
7. Create `SourceMonitor::Analytics::ScrapeRecommendations` for candidate computation
8. Confirmation modal via Stimulus controller
