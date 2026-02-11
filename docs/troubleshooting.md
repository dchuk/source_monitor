# Troubleshooting Guide

This guide lists common issues you might encounter while installing, upgrading, or operating SourceMonitor, along with concrete steps to resolve them.

## 1. Mount Path Returns 404

- Ensure the install generator added `mount SourceMonitor::Engine, at: "/source_monitor"` (or your custom path) inside the host `config/routes.rb`.
- Restart the Rails server after modifying routes.
- Confirm your host application routes are reloaded (run `rbenv exec bin/rails routes | grep source_monitor`).

## 2. Migrations or Solid Queue Tables Are Missing

- Run `rbenv exec bin/rails railties:install:migrations FROM=source_monitor` followed by `rbenv exec bin/rails db:migrate`.
- If you see duplicate migration timestamps, remove the older copy before rerunning the installer.
- For Solid Queue tables, verify the host database contains the `solid_queue_*` tables shipped with the engine migration or run `rbenv exec bin/rails solid_queue:install` for a dedicated queue database.

## 3. Dashboard Metrics Show "Unavailable"

- Solid Queue metrics require the `solid_queue` tables—see issue 2 above.
- Ensure at least one Solid Queue worker is running; the dashboard reads visibility data via `SourceMonitor::Jobs::Visibility`.
- When using mission control integration, keep `config.mission_control_dashboard_path` pointing at a valid route helper; otherwise the dashboard hides the link.

## 4. Recurring Jobs Not Running

- **Symptoms:** Fetch scheduling, scrape scheduling, and cleanup jobs never fire. Sources never auto-fetch on their configured intervals.
- Check that your dispatcher config in `config/queue.yml` (or `config/solid_queue.yml`) includes `recurring_schedule: config/recurring.yml` under the `dispatchers:` section.
- Without this key, Solid Queue's dispatcher will not load the recurring schedule even though `config/recurring.yml` exists and contains the correct job entries.
- **Fix:** Add the following to your dispatcher config and restart workers:
  ```yaml
  dispatchers:
    - polling_interval: 1
      batch_size: 500
      recurring_schedule: config/recurring.yml
  ```

## 5. Jobs Not Processing with bin/dev

- **Symptoms:** `bin/dev` starts the web server but jobs never run. Running `bin/rails solid_queue:start` manually works fine.
- Check that `Procfile.dev` includes a `jobs:` line:
  ```
  jobs: bundle exec rake solid_queue:start
  ```
- Most Rails 8 apps use foreman or overmind via `bin/dev`. Without a `jobs:` entry, the process manager only starts the web server and asset watchers -- Solid Queue workers are not launched.
- **Fix:** Add the `jobs:` line to `Procfile.dev` and restart `bin/dev`.

## 6. Realtime Updates Do Not Stream

- Confirm Action Cable is mounted and `ApplicationCable` classes exist (see installation guide).
- In production, verify WebSocket proxy settings allow the `/cable` endpoint.
- When switching to Redis, add `config.realtime.adapter = :redis` and `config.realtime.redis_url` in the initializer, then restart web and worker processes.
- For Solid Cable, check that the `solid_cable_messages` table exists and that no other process clears it unexpectedly.

## 7. Fetch Jobs Keep Failing

- Review the most recent fetch log entry for the source; it stores the HTTP status, error class, and error message.
- Increase `config.http.timeout` or `config.http.retry_max` if the feed is slow or prone to transient errors.
- Supply custom headers or basic auth credentials via the source form when feeds require authentication.
- Check for TLS issues on self-signed feeds; you may need to configure Faraday with custom SSL options.

## 8. Scraping Returns "Failed"

- Confirm the source has scraping enabled and the configured adapter exists.
- Override selectors in the source's scrape settings if the default Readability extraction misses key elements.
- Inspect the scrape log to see the adapter status and content length. Logs store the HTTP status and any exception raised by the adapter.
- Retry manually from the item detail page after fixing selectors.

## 9. Cleanup Rake Tasks Fail

- Pass numeric values for `FETCH_LOG_DAYS` or `SCRAPE_LOG_DAYS` environment variables (e.g., `FETCH_LOG_DAYS=30`).
- Ensure workers or the console environment have permission to soft delete (`SOFT_DELETE=true`) if you expect tombstones.
- If job classes cannot load, verify `SourceMonitor.configure` ran before calling `rake source_monitor:cleanup:*`.

## 10. Test Suite Cannot Launch a Browser

- System tests rely on Selenium + Chrome. Install Chrome/Chromium and set `SELENIUM_CHROME_BINARY` if the binary lives in a non-standard path.
- You can run `rbenv exec bin/test-coverage --verbose` to inspect failures with additional logging.

## 11. Mission Control Jobs Link Returns 404

- Mount `MissionControl::Jobs::Engine` in your host routes (for example, `mount MissionControl::Jobs::Engine, at: "/mission_control"`).
- Keep `config.mission_control_enabled = true` **and** `config.mission_control_dashboard_path` pointing at that mounted route helper. Call `SourceMonitor.mission_control_dashboard_path` in the Rails console to confirm it resolves.
- When hosting Mission Control in a separate app, provide a full URL instead of a route helper and ensure CORS/WebSocket settings allow the dashboard iframe.

## 12. Tailwind Build Fails or Admin UI Loads Without Styles

- Running `test/dummy/bin/dev` before configuring the bundling pipeline will serve the admin UI without Tailwind styles or Stimulus behaviours. This happens because the engine no longer ships precompiled assets; see `.ai/engine-asset-configuration.md:11-44` for the required npm setup.
- Fix by running `npm install` followed by `npm run build` inside the engine root so that `app/assets/builds/source_monitor/application.css` and `application.js` exist. The Rake task `app:source_monitor:assets:build` wraps the same scripts for CI usage.
- When the UI is still unstyled, confirm the dummy app can read the namespaced asset directories noted in `.ai/engine-asset-configuration.md:32-44` and restart `bin/dev` so the CSS/JS watchers reconnect.

## Still Stuck?

Collect the following and open an issue or start a discussion:

- Engine version (`SourceMonitor::VERSION`)
- Host Rails version and Ruby version
- Relevant configuration snippet from `config/initializers/source_monitor.rb`
- Recent fetch/scrape log entries or stack traces

We track known issues and roadmap items in `.ai/tasks.md`; check the next slice to see if your problem is already scheduled.
