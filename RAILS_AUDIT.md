# Rails Best Practices Audit — 2026-03-14

## Executive Summary

5 parallel agents audited the entire SourceMonitor engine codebase across models, controllers, services/jobs/pipeline, views/frontend, and testing layers.

| Severity | Remaining | Already Fixed |
|----------|-----------|---------------|
| **HIGH** | 6 | 0 |
| **MEDIUM** | 17 | 10 |
| **LOW** | 21 | 9 |
| **Total** | **44** | **19** |

**Overall verdict:** The codebase is well-structured for an engine of this complexity. Routes follow CRUD conventions, concerns are well-scoped, and the Hotwire frontend has solid fundamentals. Recent milestone work (phases 01-06) already resolved ~19 findings. The remaining gaps are primarily **business logic in jobs** (violates "shallow jobs" convention) and **duplicated logic** across pipeline layers.

> **Note:** 19 findings from the initial 63 were already addressed by commits in the recent ui-fixes-and-smart-scraping milestone. These are marked ~~strikethrough~~ below. The counts above reflect only unresolved findings.

---

## Table of Contents

- [HIGH Severity Findings](#high-severity-findings)
- [MEDIUM Severity Findings](#medium-severity-findings)
- [LOW Severity Findings](#low-severity-findings)
- [Top 10 Actions](#top-10-actions-prioritized-by-impacteffort-ratio)
- [Positive Observations](#positive-observations)

---

## HIGH Severity Findings

### H1. LogCleanupJob orphans LogEntry records

- **File(s):** `app/jobs/source_monitor/log_cleanup_job.rb:42-49`
- **Current:** Uses `batch.delete_all` on FetchLog/ScrapeLog records. These models have `has_one :log_entry, dependent: :destroy`, but `delete_all` skips callbacks, orphaning LogEntry records.
- **Recommended:** Delete LogEntry records first by `loggable_type`/`loggable_id`, then delete the log records. Or use `destroy_in_batches`.
- **Rationale:** Orphaned LogEntry records accumulate over time, consuming disk space and corrupting the unified logs view. The `dependent: :destroy` declaration shows cascade was intended.
- **Effort:** short

### H2. ImportOpmlJob contains 160 lines of business logic

- **File(s):** `app/jobs/source_monitor/import_opml_job.rb:14-157`
- **Current:** The job contains entry selection, deduplication, source creation, attribute building, broadcast logic, and error aggregation. This is multi-model orchestration (Source, ImportHistory, ImportSession) in a job.
- **Recommended:** Extract to `SourceMonitor::ImportSessions::OPMLImporter` service. The job becomes a 5-line delegation.
- **Rationale:** Violates "shallow jobs: only deserialization + delegation." Import logic cannot be invoked synchronously (console, tests) without going through ActiveJob. Spans 3+ models, qualifying for a service object.
- **Effort:** medium

### H3. ScrapeItemJob contains rate-limiting, state management, and deferral logic

- **File(s):** `app/jobs/source_monitor/scrape_item_job.rb:14-57`
- **Current:** Checks scraping-enabled status, computes time-until-scrape-allowed, manages state transitions (`mark_processing!`, `mark_failed!`, `clear_inflight!`), and re-enqueues itself with a delay.
- **Recommended:** Move pre-flight checks and state management into `Scraping::Runner`. Job becomes a one-liner delegation.
- **Rationale:** Rate-limiting in `time_until_scrape_allowed` duplicates near-identical logic in `Scraping::Enqueuer#time_rate_limited?`. Two places to maintain the same business rule.
- **Effort:** medium

### H4. DownloadContentImagesJob contains multi-model orchestration

- **File(s):** `app/jobs/source_monitor/download_content_images_job.rb:17-49`
- **Current:** Builds ItemContent, downloads images, creates ActiveStorage blobs, rewrites HTML, and updates the item.
- **Recommended:** Extract to `SourceMonitor::Images::Processor`. Job delegates with a single call.
- **Rationale:** Multi-model orchestration (Item, ItemContent, ActiveStorage::Blob) belongs in a pipeline class, not a job.
- **Effort:** short

### H5. Scrape rate-limiting duplicated in two places

- **File(s):** `app/jobs/source_monitor/scrape_item_job.rb:47-57` and `lib/source_monitor/scraping/enqueuer.rb:129-143`
- **Current:** Both compute time since last scrape vs. `min_scrape_interval`. The Enqueuer defers the job, and the Job re-checks and defers again.
- **Recommended:** Remove the check from `ScrapeItemJob`. The Enqueuer already handles deferral at enqueue time. If race conditions are a concern, have the job delegate to a runner that calls the Enqueuer.
- **Rationale:** Redundant DB queries and divergence risk if one is updated without the other.
- **Effort:** quick

### H6. `Source.destroy_all` in pagination tests is not parallel-safe

- **File(s):** `test/controllers/source_monitor/sources_controller_test.rb:252,264,276,286,297,311,322`
- **Current:** Seven tests call `Source.destroy_all` to get a clean slate for pagination counting. With thread-based parallelism, this can race with other threads.
- **Recommended:** Scope assertions to test-created records using a naming pattern or tracking IDs. Or use a dedicated test class with proper isolation.
- **Rationale:** Violates the project's own documented isolation rule in `TEST_CONVENTIONS.md` section 6.
- **Effort:** medium

---

## MEDIUM Severity Findings

### Models & Concerns

#### M1. `health_status` default mismatch between model and database

- **File(s):** `app/models/source_monitor/source.rb:37` vs `db/schema.rb:384`
- **Current:** Model declares `attribute :health_status, :string, default: "working"` but schema has `default: "healthy"`. A Source created in Ruby gets `"working"`, one via raw SQL gets `"healthy"`.
- **Recommended:** Align the defaults. Add `validates :health_status, inclusion: { in: HEALTH_STATUS_VALUES }`.
- **Effort:** quick

#### M2. Missing `health_status` validation

- **File(s):** `app/models/source_monitor/source.rb:44-51`
- **Current:** `fetch_status` has an inclusion validation; `health_status` has none. Any arbitrary string can be stored.
- **Recommended:** Add `HEALTH_STATUS_VALUES = %w[healthy working declining failing].freeze` and `validates :health_status, inclusion: { in: HEALTH_STATUS_VALUES }`.
- **Effort:** quick

#### M3. `Item#soft_delete!` counter cache fragility

- **File(s):** `app/models/source_monitor/item.rb:69-83`
- **Current:** Manually calls `Source.decrement_counter(:items_count, source_id)` after `update_columns`. No corresponding `restore!` method to re-increment.
- **Recommended:** Add a `restore!` method for symmetry. Consider extracting soft-delete into a concern.
- **Effort:** short

#### M4. Duplicated `sync_log_entry` callback across 3 log models

- **File(s):** `app/models/source_monitor/fetch_log.rb:28`, `scrape_log.rb:20`, `health_check_log.rb:20`
- **Current:** All three define identical `after_save :sync_log_entry` callbacks.
- **Recommended:** Move into the `Loggable` concern.
- **Effort:** quick

### Controllers & Routes

#### M5. No `rescue_from ActiveRecord::RecordNotFound`

- **File(s):** `app/controllers/source_monitor/application_controller.rb`
- **Current:** No rescue_from handlers. A missing record raises 500 in production.
- **Recommended:** Add a Turbo-aware RecordNotFound handler that renders a toast + 404.
- **Rationale:** As a mountable engine, SourceMonitor should handle its own common exceptions gracefully.
- **Effort:** short

#### M6. Duplicated `set_source` across 7 controllers

- **File(s):** `source_fetches_controller.rb`, `source_retries_controller.rb`, `source_bulk_scrapes_controller.rb`, `source_health_checks_controller.rb`, `source_health_resets_controller.rb`, `source_favicon_fetches_controller.rb`, `source_scrape_tests_controller.rb`
- **Current:** Each defines identical `def set_source; @source = Source.find(params[:source_id]); end`.
- **Recommended:** Extract to a `SetSource` concern.
- **Effort:** quick

#### M7. `fallback_user_id` creates users in host-app tables

- **File(s):** `app/controllers/source_monitor/import_sessions_controller.rb:244-276`
- **Current:** When no authenticated user exists, creates a "guest" user by introspecting column schema.
- **Recommended:** Guard behind `Rails.env.development?` or remove entirely. An engine should never create records in host-app tables.
- **Effort:** short

#### M8. ImportSessions controller concerns contain significant business logic

- **File(s):** `app/controllers/source_monitor/import_sessions/opml_parser.rb` (128 lines), `entry_annotation.rb` (187 lines), `health_check_management.rb` (112 lines), `bulk_configuration.rb` (106 lines)
- **Current:** XML parsing, URL validation, duplicate detection, job enqueueing, database locking — all in controller concerns.
- **Recommended:** Extract pure-domain parts to `lib/` or `app/services/` classes. Controller concerns become thin wrappers.
- **Effort:** large

#### ~~M9. `SourcesController#index` has 47 lines of query orchestration~~ RESOLVED

- ~~Resolved by `a6d7148` (extract sources index metrics) + `795b7b8` (SourcesFilterPresenter) + `cafefc2` (FilterDropdownComponent)~~

#### M10. `BulkScrapeEnablementsController` contains business logic

- **File(s):** `app/controllers/source_monitor/bulk_scrape_enablements_controller.rb:13-19`
- **Current:** `update_all` with field combination for enabling scraping is in the controller.
- **Recommended:** Extract to `Source.enable_scraping!(ids)` class method.
- **Effort:** quick

#### M11. Excessive `update_column` usage in ImportSessions flow

- **File(s):** `app/controllers/source_monitor/import_sessions_controller.rb` (11 calls)
- **Current:** Skips validations for `current_step` and `selected_source_ids` changes.
- **Recommended:** Encapsulate in model methods like `ImportSession#advance_to!(step)`.
- **Effort:** short

### Services, Jobs & Pipeline

#### M12. FaviconFetchJob contains cooldown and attachment logic

- **File(s):** `app/jobs/source_monitor/favicon_fetch_job.rb:17-42`
- **Current:** Cooldown checking duplicated with `SourceUpdater#enqueue_favicon_fetch_if_needed`.
- **Recommended:** Extract to `Favicons::FetchService`. Consolidate cooldown in `Favicons::CooldownCheck`.
- **Effort:** short

#### M13. ImportSessionHealthCheckJob contains lock management

- **File(s):** `app/jobs/source_monitor/import_session_health_check_job.rb:18-63`
- **Current:** Acquires row lock, merges results, updates state, broadcasts.
- **Recommended:** Extract to `ImportSessions::HealthCheckUpdater`.
- **Effort:** short

#### M14. SourceHealthCheckJob contains broadcast and toast formatting

- **File(s):** `app/jobs/source_monitor/source_health_check_job.rb:29-83`
- **Current:** `toast_payload`, `broadcast_outcome`, `trigger_fetch_if_degraded` are all presentation/side-effect logic.
- **Recommended:** Move into `Health::SourceHealthCheckOrchestrator`.
- **Effort:** short

#### ~~M15. Inconsistent Result pattern across pipeline classes~~ PARTIALLY RESOLVED

- ~~`e03723d` added Result structs to completion handlers; `5bd538a` wired Result usage in FetchRunner~~
- **Remaining:** `FeedFetcher::Result` still lacks `success?`. No shared base `SourceMonitor::Result` class exists yet.
- **Effort:** medium

#### ~~M16. Retry logic split across 4 locations~~ RESOLVED

- ~~Resolved by `4ff8884` (extract FetchFeedJob retry orchestrator service)~~

#### M17. Swallowed exceptions in ensure/rescue blocks

- **File(s):** `feed_fetcher.rb:331`, `scraping/state.rb:68`, `source_health_check_job.rb:46-47`
- **Current:** `rescue StandardError => nil` silently swallows failures.
- **Recommended:** Add `Rails.logger.warn` in rescue blocks.
- **Effort:** quick

#### M18. StalledFetchReconciler uses fragile PG JSON operator on SolidQueue internals

- **File(s):** `lib/source_monitor/fetching/stalled_fetch_reconciler.rb:107`
- **Current:** `where("arguments::jsonb -> 'arguments' ->> 0 = ?", source.id.to_s)` — fragile if SolidQueue changes serialization.
- **Recommended:** Add version comment and regression test.
- **Effort:** quick

### Views & Frontend

#### M19. Database queries executed in view templates

- **File(s):** `items/_details.html.erb:6-7`, `sources/_bulk_scrape_modal.html.erb:3-11`
- **Current:** `item.scrape_logs.order(...).limit(5)` and similar queries directly in ERB.
- **Recommended:** Move to controllers and pass as locals, or extend presenters.
- **Note:** `sources/_details.html.erb` was partially addressed by `SourceDetailsPresenter` (`7c2604b`), but items and bulk scrape modal still have inline queries.
- **Effort:** short

#### M20. StatusBadge markup duplicated 12+ times

- **File(s):** `sources/_row.html.erb`, `sources/_details.html.erb`, `dashboard/_recent_activity.html.erb`, `items/_details.html.erb`, `items/index.html.erb`, `logs/index.html.erb`
- **Current:** Hand-crafted `<span class="inline-flex items-center rounded-full ...">` with conditional spinners.
- **Recommended:** Create a `StatusBadgeComponent`.
- **Note:** `IconComponent` was added (`caa4e69`) for SVG icons, but status badges are a separate pattern that still needs extraction.
- **Effort:** medium

#### ~~M21. Missing SourceDetailsPresenter~~ PARTIALLY RESOLVED

- ~~`SourceDetailsPresenter` added in `7c2604b`~~
- **Remaining:** `ItemDetailsPresenter`, `FetchLogPresenter`, `ScrapeLogPresenter`, `SourceRowPresenter` still missing.
- **Effort:** medium (each)

#### M22. Modal missing `role="dialog"` and `aria-modal`

- **File(s):** `sources/_bulk_scrape_modal.html.erb`, `sources/_bulk_scrape_enable_modal.html.erb`
- **Current:** Modal panels are plain `<div>` elements.
- **Recommended:** Add `role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing to heading.
- **Effort:** quick

#### M23. Modal controller lacks focus trapping

- **File(s):** `app/assets/javascripts/source_monitor/controllers/modal_controller.js`
- **Current:** Handles Escape and backdrop click but doesn't trap focus. Users can Tab out.
- **Recommended:** Implement focus trapping with `inert` attribute on background elements.
- **Rationale:** WCAG 2.1 SC 2.4.3 requires meaningful focus order.
- **Effort:** medium

#### M24. Logs index missing Turbo Frame for filter/pagination

- **File(s):** `app/views/source_monitor/logs/index.html.erb`
- **Current:** No Turbo Frame wrapping. `form_with` uses `local: true` disabling Turbo. Full page reload on filter.
- **Recommended:** Wrap table+pagination in a Turbo Frame. Sources and Items both use this pattern.
- **Effort:** medium

#### M25. Button styles inconsistent across templates

- **File(s):** Virtually every template
- **Current:** 5-6 button variants with inconsistent `font-semibold` vs `font-medium`, padding variations.
- **Recommended:** Extract button variants to `@apply` CSS classes or a `ButtonComponent`.
- **Effort:** medium

#### M26. `ApplicationHelper` is 333 lines with mixed concerns

- **File(s):** `app/helpers/source_monitor/application_helper.rb`
- **Current:** 20+ methods spanning badges, favicons, pagination, URLs, formatting.
- **Recommended:** Split into focused helper modules: `StatusBadgeHelper`, `FaviconHelper`, `PaginationHelper`, `FetchIntervalHelper`, `ExternalLinkHelper`.
- **Note:** `SourcesFilterPresenter` (`795b7b8`) and `FilterDropdownComponent` (`cafefc2`) extracted some filter logic, but the helper itself is still large.
- **Effort:** medium

### Testing

#### ~~M27. `create_item!` factory underused~~ PARTIALLY RESOLVED

- ~~`18692f6` centralized factory helpers into ModelFactories module~~
- **Remaining:** Many test files still use manual `Item.create!` instead of the now-centralized `create_item!`. Migration to the shared factories is incomplete.
- **Effort:** medium

---

## LOW Severity Findings

### Controllers & Routes

#### L1. `new` action delegates to `create` in ImportSessionsController (GET creates records)
- `import_sessions_controller.rb:35-37` — quick

#### L2. `BulkScrapeEnablementsController` accesses params without strong params wrapper
- `bulk_scrape_enablements_controller.rb:6` — quick

#### L3. `SourceScrapeTestsController#create` builds result hash inline (should be presenter)
- `source_scrape_tests_controller.rb:14-24` — short

#### L4. `SourceHealthChecksController` embeds Tailwind classes in controller
- `source_health_checks_controller.rb:25-31` — quick

#### L5. Inconsistent Turbo Stream response patterns (StreamResponder vs raw arrays)
- Multiple controllers — short

#### ~~L6. Broad `rescue StandardError` in action controllers~~ RESOLVED
- ~~Resolved by `6bcd0ac` and `19bb3b8` (transient vs fatal error classification in FaviconFetchJob and DownloadContentImagesJob) + `911c17e` (deadlock rescue + error logging)~~

#### L7. `SanitizesSearchParams` uses `to_unsafe_h` without documentation
- `concerns/source_monitor/sanitizes_search_params.rb:45` — quick

#### L8. `SourcesController#update` contains conditional job-enqueue logic
- `sources_controller.rb:94-109` — short

### Models

#### L9. Ransacker subqueries could be extracted to `Source::SearchableAttributes` concern
- `source.rb:79-103` — short

#### L10. Missing `scraping_enabled` / `scraping_disabled` scopes
- `source.rb` — quick

#### L11. `ItemContent#compute_feed_word_count` reaches through association (minor Demeter violation)
- `item_content.rb:33-39` — quick

#### L12. `ImportHistory` missing chronological validation and JSONB attribute declarations
- `import_history.rb` — quick

### Services, Jobs & Pipeline

#### ~~L13. `FetchFeedJob#should_run?` scheduling logic~~ PARTIALLY RESOLVED
- ~~`4ff8884` extracted retry orchestrator, reducing job logic. `should_run?` guard still exists but is simpler.~~

#### L14. Backward-compatibility forwarding methods in FeedFetcher (12) and ItemCreator (18)
- `feed_fetcher.rb:393-404`, `item_creator.rb:179-197` — medium

#### L15. FeedFetcher constants duplicated from AdaptiveInterval
- `feed_fetcher.rb:30-36` — quick

#### L16. Inconsistent logger guard pattern (20+ occurrences of full guard)
- Nearly every pipeline file — short

#### L17. `Images::Downloader` creates raw Faraday connection instead of `HTTP.client`
- `images/downloader.rb:46-58` — quick

#### L18. `Logs::Query` is good; `Scheduler` queries could be extracted
- `scheduler.rb:55-89`, `scraping/scheduler.rb:38-45` — short

#### L19. CloudflareBypass tries all 4 user agents sequentially (could cause 60s+ fetch)
- `fetching/cloudflare_bypass.rb:39-49` — quick

### Views & Frontend

#### L20. Items and Logs index pagination not using shared `_pagination.html.erb` partial
- `items/index.html.erb:124-146`, `logs/index.html.erb:186-209` — short

#### L21. Scrape test result markup duplicated between show page and modal
- `source_scrape_tests/show.html.erb:8-56`, `_result.html.erb:12-60` — quick

#### L22. Card panel pattern repeated ~20 times (potential `PanelComponent`)
- Various dashboard/sources/items views — medium

#### L23. Error display duplicated across new/edit views (should be `_form_errors` partial)
- `sources/new.html.erb:4-13`, `edit.html.erb:4-13` — quick

#### ~~L24. Dropdown controller registers global click listener eagerly~~ RESOLVED
- ~~Resolved by `491fae1` (simplify dropdown controller and remove JS globals)~~

#### ~~L25. Notification controller has dead `applyLevelDelay()` method~~ RESOLVED
- ~~Resolved by `15e7d53` (remove dead JS error delay override and document constants)~~

#### ~~L26. Dismiss button SVG missing `aria-label`, should use `IconComponent`~~ PARTIALLY RESOLVED
- ~~`4c56789` replaced inline SVGs with IconComponent. Check if this specific dismiss button was included.~~

#### L27. `FilterDropdownComponent` uses inline `onchange` instead of Stimulus action
- `filter_dropdown_component.rb:48,55` — short

### Testing

#### L28. Duplicated `configure_authentication` helper across 4 test files
- 4 test files — quick

#### ~~L29. Duplicated SolidQueue table purge logic~~ PARTIALLY RESOLVED
- ~~`54617b8` created SystemTestHelpers module with shared purge method. Some lib tests may still inline it.~~

#### L30. No test files for FetchLogsController, ScrapeLogsController, ImportHistory model
- Missing test files — short

---

## Top 10 Actions (prioritized by impact/effort ratio)

| # | Finding | Severity | Effort | Category |
|---|---------|----------|--------|----------|
| 1 | **H1** — Fix LogCleanupJob orphaned LogEntry records | HIGH | short | Data integrity |
| 2 | **H5** — Remove duplicated scrape rate-limiting from ScrapeItemJob | HIGH | quick | DRY |
| 3 | **M6** — Extract `set_source` into shared concern | MEDIUM | quick | DRY |
| 4 | **M1+M2** — Align `health_status` default + add validation | MEDIUM | quick | Correctness |
| 5 | **M4** — Move `sync_log_entry` callback into Loggable concern | MEDIUM | quick | DRY |
| 6 | **M5** — Add `rescue_from RecordNotFound` | MEDIUM | short | Robustness |
| 7 | **H4** — Extract DownloadContentImagesJob orchestration | HIGH | short | Convention |
| 8 | **H6** — Fix pagination test parallel-safety | HIGH | medium | Test reliability |
| 9 | **H2** — Extract ImportOpmlJob business logic to service | HIGH | medium | Convention |
| 10 | **M20** — Create StatusBadgeComponent | MEDIUM | medium | DRY/Consistency |

> **Previously in Top 10, now resolved:** M9 (SourcesController#index metrics — extracted to presenters), M16 (retry logic consolidation — extracted to RetryOrchestrator service)

---

## Positive Observations

The audit identified many areas where the codebase excels:

- **CRUD route design** is textbook — every action is a resource (`source_fetches`, `source_retries`, etc.)
- **Loggable concern** is exemplary single-purpose shared behavior
- **Boolean usage** correctly follows state-as-records convention (all booleans are technical flags)
- **Association declarations** include `inverse_of`, `dependent: :destroy`, and thorough indexing
- **Factory helpers** (`ModelFactories`) have good defaults with `SecureRandom` for parallel safety
- **VCR/WebMock separation** is clean (VCR for real feeds, WebMock for controlled scenarios)
- **Source turbo responses** concern is well-focused on response rendering
- **Table styling** is consistent across all views
- **Test conventions** are documented in `TEST_CONVENTIONS.md` with clear guidance
- **Thread-safe config reset** with `SourceMonitor.reset_configuration!`
- **Active Storage guarding** with `if defined?(ActiveStorage)` checks
- **Strong params** via `Sources::Params.sanitize` with explicit allowlist
- **Pipeline architecture** — all service objects are justified multi-model orchestrators

---

*Generated by `/rails-audit` command. Re-run to refresh findings.*
