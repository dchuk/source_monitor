# Version-Specific Upgrade Notes

Version-specific migration notes for each major/minor version transition. Agents should reference this file when guiding users through multi-version upgrades.

## 0.12.2 to 0.12.3

**Key changes:**
- UI fixes: menu icon rendering (gear -> vertical ellipsis), modal Stimulus controller scope, cross-page select-all for bulk scraping recommendations

**Action items:**
1. `bundle update source_monitor`
2. No migrations, config changes, or breaking changes.

## 0.12.1 to 0.12.2

**Key changes:**
- Bug fix: Health check status vocabulary aligned (`working`/`failing`) so progress counter updates correctly during OPML import

**Action items:**
1. `bundle update source_monitor`
2. No migrations, config changes, or breaking changes.

## 0.11.x to 0.12.0

**Key changes:**
- 2 new migrations: composite indexes on `sourcemon_fetch_logs`, `sourcemon_scrape_logs`, and `sourcemon_health_check_logs` (on `source_id, created_at`), and `health_status` column default corrected to `"working"`.
- 5 background jobs extracted to service classes: `ScrapeItemJob` -> `Scraping::Runner`, `DownloadContentImagesJob` -> `Images::Processor`, `FaviconFetchJob` -> `Favicons::Fetcher`, `SourceHealthCheckJob` -> `Health::SourceHealthCheckOrchestrator`, `ImportSessionHealthCheckJob` -> `ImportSessions::HealthCheckUpdater`. Job arguments and queue assignments are unchanged.
- New ViewComponents: `StatusBadgeComponent`, `IconComponent`, `FilterDropdownComponent`.
- New presenters: `SourceDetailsPresenter`, `SourcesFilterPresenter`.
- New model methods: `Source.enable_scraping!(ids)`, `Item#restore!`, `health_status` validation against the 4 permitted values.

**Action items:**
1. Copy and run migrations:
   ```bash
   bin/rails source_monitor:install:migrations
   bin/rails db:migrate
   ```
2. No breaking changes -- all existing initializer configuration and job interfaces remain valid.
3. No configuration changes required.
4. ViewComponents and presenters are available for use in custom views but are not required.

## 0.10.2 to 0.11.0

**Key changes:**
- Health status simplified from 7 values to 4 (`working`, `declining`, `improving`, `failing`). Auto-pause tracked as operational state via `auto_paused_at`/`auto_paused_until` columns.
- New `consecutive_fetch_failures` column (integer, NOT NULL, default 0) on `sourcemon_sources` for streak-based health detection.
- New `error_category` column (string, nullable) on `sourcemon_fetch_logs` for classifying failure types.
- New `config.scraping.scrape_recommendation_threshold` (default 200) controls the word-count threshold for dashboard scrape recommendations.
- Dashboard pagination for sources and items lists.
- Automatic Cloudflare bypass via cookie replay and UA rotation (no configuration needed).
- Smart scrape recommendations widget on the dashboard highlights sources that may benefit from scraping.
- New third queue: `source_monitor_maintenance` for non-fetch jobs (health checks, cleanup, favicon, images, OPML import).
- `config.fetching.scheduler_batch_size` (default `25`, was hardcoded `100`) and `config.fetching.stale_timeout_minutes` (default `5`, was `10`).
- Fixed-interval sources now get +/-10% jitter on `next_fetch_at`.
- Fetch pipeline error handling hardened: DB errors propagate, `ensure` block guarantees status reset.

**Action items:**
1. **Action required:** If your initializer sets `config.health.warning_threshold`, remove that line. The setting no longer exists.
2. **Action required:** Add the maintenance queue to your `solid_queue.yml`:
   ```yaml
   source_monitor_maintenance:
     concurrency: <%= ENV.fetch("SOURCE_MONITOR_MAINTENANCE_CONCURRENCY", 1) %>
   ```
3. If your host app queries `health_status` directly (e.g., `Source.where(health_status: "healthy")`), update to use the new values (`working`, `declining`, `improving`, `failing`).
4. If you have many overdue sources after upgrading, run `bin/rails source_monitor:maintenance:stagger_fetch_times` to break the thundering herd.
5. All existing configuration (except `warning_threshold`) remains valid.

## 0.7.x to 0.8.0

**Key changes:**
- Default HTTP User-Agent changed from `SourceMonitor/<version>` to `Mozilla/5.0 (compatible; SourceMonitor/<version>)` with browser-like headers (Accept-Language, DNT, Referer). Prevents bot-blocking by feed servers.
- Default `max_in_flight_per_source` changed from `25` to `nil` (unlimited). If you relied on the previous default for per-source rate limiting, set it explicitly.
- Successful manual health checks on degraded sources now trigger a feed fetch for faster recovery.
- Automatic source favicons via Active Storage with multi-strategy discovery (direct `/favicon.ico`, HTML `<link>` parsing, Google Favicon API fallback)
- New configuration section: `config.favicons` with `enabled`, `fetch_timeout`, `max_download_size`, `retry_cooldown_days`, and `allowed_content_types` settings
- Colored initials placeholder shown when no favicon is available or Active Storage is not installed
- OPML imports trigger favicon fetches for each imported source with a `website_url`
- Toast notifications capped at 3 visible with "+N more" badge, click-to-expand, and "Clear all" button
- Error-level toasts auto-dismiss after 10 seconds (vs 5 seconds for info/success)

**Action items:**
1. Re-run `bin/rails source_monitor:upgrade` to get updated initializer template
2. If you explicitly set `config.http.user_agent`, your value is preserved. Otherwise the new browser-like default applies automatically.
3. If you need per-source scrape rate limiting, add `config.scraping.max_in_flight_per_source = 25` (or your preferred value) to your initializer
4. If using Active Storage, favicons are enabled by default -- no action needed
5. If NOT using Active Storage, favicons are silently disabled -- no action needed
6. Toast stacking is automatic -- no configuration needed
7. No breaking changes -- all existing configuration remains valid

## 0.3.x to 0.4.0

**Released:** 2026-02-12

**Key changes:**
- Install generator now auto-patches `Procfile.dev` and `queue.yml` dispatcher config
- New Active Storage image download feature (opt-in via `config.images.download_to_active_storage`)
- SSL certificate store configuration added to HTTPSettings
- RecurringScheduleVerifier and SolidQueueVerifier enhanced with better remediation messages
- Netflix Tech Blog VCR cassette regression test added

**Action items:**
1. Re-run `bin/rails source_monitor:upgrade` (or `bin/rails generate source_monitor:install`) to get Procfile.dev and queue.yml patches
2. If using Active Storage image downloads, add `config.images.download_to_active_storage = true` to initializer
3. If experiencing SSL certificate errors, new `config.http.ssl_ca_file`, `config.http.ssl_ca_path`, and `config.http.ssl_verify` settings are available
4. No breaking changes -- all existing configuration remains valid

## 0.2.x to 0.3.0

**Released:** 2026-02-10

**Key changes:**
- Major refactoring: FeedFetcher, Configuration, ImportSessionsController, ItemCreator all extracted into smaller modules
- Ruby autoload replaces eager requires in `lib/source_monitor.rb`
- LogEntry no longer uses hard-coded table name
- Skills system added (14 `sm-*` skills)
- Upgraded to Ruby 4.0.1 and Rails 8.1.2

**Action items:**
1. If you monkey-patched or referenced internal classes (FeedFetcher internals, Configuration nested classes), check that your references still resolve
2. Run `bin/rails source_monitor:upgrade` to copy any new migrations
3. Optionally install skills: `bin/rails source_monitor:skills:install`
4. No configuration changes required -- public API unchanged

## 0.1.x to 0.2.0

**Released:** 2025-11-25

**Key changes:**
- OPML import wizard added with multi-step flow
- ImportHistory model and migrations added
- Health check enqueuing and Turbo Stream updates during wizard

**Action items:**
1. Copy and run new migrations: `bin/rails railties:install:migrations FROM=source_monitor && bin/rails db:migrate`
2. No configuration changes required

## Future Versions

Template for documenting future upgrades:

```
## X.Y.Z to A.B.C
Released: YYYY-MM-DD

Key changes:
- ...

Action items:
1. ...

Deprecations:
- `old_option` replaced by `new_option` (warning in A.B.C, removal planned for D.E.F)
```
