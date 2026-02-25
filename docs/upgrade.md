# SourceMonitor Upgrade Guide

This guide covers upgrading SourceMonitor to a new gem version in your host Rails application.

## General Upgrade Steps

1. Review the [CHANGELOG](../CHANGELOG.md) for changes between your current and target versions
2. Update your Gemfile version constraint and run `bundle update source_monitor`
3. Run the upgrade command: `bin/rails source_monitor:upgrade`
4. Apply database migrations if new ones were copied: `bin/rails db:migrate`
5. Address any deprecation warnings in your initializer (see Deprecation Handling below)
6. Run verification: `bin/rails source_monitor:setup:verify`
7. Restart your web server and background workers

## Quick Upgrade (Most Cases)

```bash
# 1. Update the gem
bundle update source_monitor

# 2. Run the upgrade command (handles migrations, generator, verification)
bin/rails source_monitor:upgrade

# 3. Migrate if needed
bin/rails db:migrate

# 4. Restart
# (restart web server and Solid Queue workers)
```

## Deprecation Handling

When upgrading, you may see deprecation warnings in your Rails log:

```
[SourceMonitor] DEPRECATION: 'http.old_option' was deprecated in v0.5.0 and replaced by 'http.new_option'.
```

To resolve:
1. Open `config/initializers/source_monitor.rb`
2. Find the deprecated option (e.g., `config.http.old_option = value`)
3. Replace with the new option from the warning message (e.g., `config.http.new_option = value`)
4. Restart and verify the warning is gone

If a removed option raises an error (`SourceMonitor::DeprecatedOptionError`), you must update the initializer before the app can boot.

## Version-Specific Notes

### Upgrading to 0.10.0 (from 0.9.x)

**What changed:**
- New third queue: `source_monitor_maintenance` separates non-fetch jobs from the fetch pipeline. Health checks, cleanup, favicon, image download, and OPML import jobs now use the maintenance queue.
- Scheduler batch size configurable via `config.fetching.scheduler_batch_size` (default reduced from 100 to 25).
- Stale fetch timeout configurable via `config.fetching.stale_timeout_minutes` (default reduced from 10 to 5).
- Fixed-interval sources now receive ±10% jitter on `next_fetch_at`.
- Fetch pipeline error handling hardened: DB errors propagate, broadcast errors are still rescued, `ensure` block guarantees status reset.
- New rake task: `source_monitor:maintenance:stagger_fetch_times` distributes overdue sources across a time window.

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails source_monitor:upgrade
bin/rails db:migrate
```

**Notes:**
- **Action required:** Update your `solid_queue.yml` to include the new maintenance queue. Add:
  ```yaml
  source_monitor_maintenance:
    concurrency: <%= ENV.fetch("SOURCE_MONITOR_MAINTENANCE_CONCURRENCY", 1) %>
  ```
- If you have many sources that are overdue after upgrading, run `bin/rails source_monitor:maintenance:stagger_fetch_times` to break the thundering herd.
- The default batch size (25) and stale timeout (5 min) are tuned for 1-CPU/2GB servers. Scale up via `config.fetching.scheduler_batch_size` and `config.fetching.stale_timeout_minutes` for larger deployments.
- No breaking changes to public API. All existing initializer configuration remains valid.

### Upgrading to 0.8.0 (from 0.7.x)

**What changed:**
- Default HTTP User-Agent changed from `SourceMonitor/<version>` to a browser-like string (`Mozilla/5.0 (compatible; SourceMonitor/<version>)`) with Accept-Language, DNT, and Referer headers. This prevents bot-blocking by feed servers.
- Default `max_in_flight_per_source` changed from `25` to `nil` (unlimited). If you relied on the previous default, add `config.scraping.max_in_flight_per_source = 25` to your initializer.
- Successful manual health checks on degraded sources now trigger a feed fetch to allow faster recovery.
- Automatic source favicons via Active Storage (see `config.favicons` section).
- Toast notifications capped at 3 visible with "+N more" overflow badge and "Clear all" button.

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails source_monitor:upgrade
bin/rails db:migrate
```

**Notes:**
- No breaking changes for most users. The User-Agent and `max_in_flight_per_source` defaults changed, but both are backward-compatible.
- If you explicitly set `config.http.user_agent` in your initializer, your custom value is preserved.
- If your scraping workload requires per-source rate limiting, set `config.scraping.max_in_flight_per_source` explicitly.
- Favicons require Active Storage in the host app; apps without it see placeholder initials with no errors.

### Upgrading to 0.4.0 (from 0.3.x)

**Released:** 2026-02-12

**What changed:**
- Install generator now auto-patches `Procfile.dev` with a Solid Queue `jobs:` entry
- Install generator now patches `config/queue.yml` dispatcher with `recurring_schedule: config/recurring.yml`
- Active Storage image download feature added (opt-in)
- SSL certificate configuration added to HTTP settings
- Enhanced verification messages for SolidQueue and RecurringSchedule verifiers

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails source_monitor:upgrade
bin/rails db:migrate
```

**Notes:**
- No breaking changes. All existing configuration remains valid.
- Re-running the generator (`bin/rails generate source_monitor:install`) will add missing `Procfile.dev` and `queue.yml` entries without overwriting existing config.
- New optional features: `config.images.download_to_active_storage = true`, `config.http.ssl_ca_file`, `config.http.ssl_ca_path`, `config.http.ssl_verify`.

### Upgrading to 0.3.0 (from 0.2.x)

**Released:** 2026-02-10

**What changed:**
- Internal refactoring: FeedFetcher, Configuration, ImportSessionsController, and ItemCreator extracted into smaller modules
- Eager requires replaced with Ruby autoload
- Skills system added (14 `sm-*` Claude Code skills)

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails source_monitor:upgrade
bin/rails db:migrate
```

**Notes:**
- No breaking changes to the public API.
- If you referenced internal classes directly (e.g., `SourceMonitor::FeedFetcher` internals), verify your code against the new module structure.
- Optionally install AI skills: `bin/rails source_monitor:skills:install`

### Upgrading to 0.2.0 (from 0.1.x)

**Released:** 2025-11-25

**What changed:**
- OPML import wizard with multi-step flow
- New `ImportHistory` model and associated migrations

**Upgrade steps:**
```bash
bundle update source_monitor
bin/rails railties:install:migrations FROM=source_monitor
bin/rails db:migrate
```

**Notes:**
- New database tables required. Run migrations after updating.
- No configuration changes needed.

## Troubleshooting

### "Already up to date" but I expected changes
- Verify the gem version actually changed: `bundle show source_monitor`
- Check `Gemfile.lock` for the resolved version
- If the `.source_monitor_version` marker was manually edited, delete it and re-run upgrade

### Migrations fail with duplicate timestamps
- Remove the duplicate migration file from `db/migrate/` (keep the newer one)
- Re-run `bin/rails db:migrate`

### Deprecation error prevents boot
- Read the error message for the replacement option
- Update your initializer before restarting
- If unsure which option to use, consult [Configuration Reference](configuration.md)

### Verification failures after upgrade
- **PendingMigrations:** Run `bin/rails db:migrate`
- **SolidQueue:** Ensure workers are running. Check `Procfile.dev` for a `jobs:` entry.
- **RecurringSchedule:** Re-run `bin/rails generate source_monitor:install` to patch `config/queue.yml`
- **ActionCable:** Configure Solid Cable or Redis adapter

For additional help, see [Troubleshooting](troubleshooting.md).

## See Also
- [Setup Guide](setup.md) -- Initial installation
- [Configuration Reference](configuration.md) -- All configuration options
- [Troubleshooting](troubleshooting.md) -- Common issues and fixes
- [CHANGELOG](../CHANGELOG.md) -- Full version history
