# SourceMonitor Setup Workflow

This guide consolidates the new guided installer, verification commands, and rollback steps so teams can onboard the engine into either a fresh Rails host or an existing application without missing prerequisites. You never need to clone the SourceMonitor repository for installation—simply add the gem to your host application's Gemfile and run the steps below.

## Prerequisites

| Requirement | Minimum | Notes |
| --- | --- | --- |
| Ruby | 4.0.1 | Use rbenv and match the engine's `.ruby-version`. |
| Rails | 8.1.2 | Run `bin/rails about` inside the host to confirm. |
| PostgreSQL | 14+ | Required for Solid Queue tables and item storage. |
| Node.js | 18+ | Needed for Tailwind/esbuild assets when the host owns node tooling. |
| Background jobs | Solid Queue (>= 0.3, < 3.0) | Add `solid_queue` to the host Gemfile if not present. |
| Realtime | Solid Cable (>= 3.0) or Redis | Solid Cable is the default; Redis requires `config.realtime.adapter = :redis`. |

## Install the Gem

Run these commands inside your host Rails application before invoking the guided workflow:

```bash
bundle add source_monitor --version "~> 0.10.0"
# or add gem "source_monitor", "~> 0.10.0" to Gemfile manually
bundle install
```

This ensures Bundler can load SourceMonitor so the commands below are available.

## Guided Setup (Recommended)

1. **Check prerequisites** (optional but fast):
   ```bash
   bin/rails source_monitor:setup:check
   ```
   This invokes the dependency checker added in Phase 10.04 and surfaces remediation text when versions or adapters are missing.

2. **Run the guided installer:**
   ```bash
   bin/source_monitor install
   ```
   - Prompts for the mount path (defaults to `/source_monitor`).
   - Ensures `gem "source_monitor"` is in the host Gemfile and runs `bundle install` via rbenv shims.
   - Runs `npm install` when `package.json` exists.
   - Executes `bin/rails generate source_monitor:install --mount-path=...`.
   - Copies migrations, deduplicates duplicate Solid Queue migrations, and reruns `bin/rails db:migrate`.
   - Updates `config/initializers/source_monitor.rb` with a navigation hint and, when desired, Devise hooks.
   - Writes a verification report at the end (same as `bin/source_monitor verify`).

3. **Start background workers:**
   ```bash
   bin/rails solid_queue:start
   ```
   The install generator automatically handles all worker configuration:
   - **Recurring jobs** are configured in `config/recurring.yml` (fetch scheduling, scraping, cleanup).
   - **Procfile.dev** is patched with a `jobs:` entry so `bin/dev` starts Solid Queue alongside the web server.
   - **Queue dispatcher** is patched with `recurring_schedule: config/recurring.yml` in `config/queue.yml` so recurring jobs load on startup.

   All three steps are idempotent. If any configuration is missing, re-run: `bin/rails generate source_monitor:install`

4. **Visit the dashboard** at the chosen mount path, create a source, and trigger “Fetch Now” to validate realtime updates and Solid Queue processing.

### Fully Non-Interactive Install

Use `--yes` to accept defaults (mount path `/source_monitor`, Devise hooks enabled if Devise detected):
```bash
bin/source_monitor install --yes
```

### Verification & Telemetry

- Re-run verification anytime:
  ```bash
  bin/source_monitor verify
  ```
  or
  ```bash
  bin/rails source_monitor:setup:verify
  ```
- Results show human-friendly lines plus a JSON blob; exit status is non-zero when any check fails.
- To persist telemetry for support, set `SOURCE_MONITOR_SETUP_TELEMETRY=true`. Logs append to `log/source_monitor_setup.log`.

## Manual Installation (Advanced)

Prefer to script each step or plug SourceMonitor into an existing deployment checklist? Use the manual flow below. It mirrors the guided CLI internals while keeping every command explicit.

### Quick Reference

| Step | Command | Purpose |
| --- | --- | --- |
| 1 | `gem "source_monitor", github: "dchuk/source_monitor"` | Add the engine to your Gemfile (skip if already present) |
| 2 | `bundle install` | Install Ruby dependencies |
| 3 | `bin/rails generate source_monitor:install --mount-path=/source_monitor` | Mount the engine, create the initializer, and configure recurring jobs |
| 4 | `bin/rails railties:install:migrations FROM=source_monitor` | Copy engine migrations (idempotent) |
| 5 | `bin/rails db:migrate` | Apply schema updates, including Solid Queue tables |
| 6 | `bin/rails solid_queue:start` | Ensure jobs process via Solid Queue |
| 6a | Handled by generator (patches `Procfile.dev`) | Ensure `bin/dev` starts Solid Queue workers |
| 6b | Handled by generator (patches `config/queue.yml`) | Wire recurring jobs into Solid Queue dispatcher |
| 7 | `bin/jobs --recurring_schedule_file=config/recurring.yml` | Start recurring scheduler (optional but recommended) |
| 8 | `bin/source_monitor verify` | Confirm Solid Queue/Action Cable readiness and emit telemetry |

> Tip: You can drop these commands directly into your CI pipeline or release scripts. The CLI uses the same services, so mixing and matching is safe.

### Step-by-step Details

1. **Add the gem** to the host `Gemfile` (GitHub edge or released version) and run `bundle install`. If your host manages node tooling, run `npm install` also.
2. **Install the engine** via `bin/rails generate source_monitor:install --mount-path=/source_monitor`. The generator mounts the engine, creates `config/initializers/source_monitor.rb`, and configures recurring Solid Queue jobs in `config/recurring.yml`. Re-running the generator is safe; it detects existing mounts/initializers and skips entries that are already present.
3. **Copy migrations** with `bin/rails railties:install:migrations FROM=source_monitor`. This brings in the SourceMonitor tables plus Solid Cable/Queue schema when needed. The command is idempotent—run it again after upgrading the gem.
4. **Apply database changes** using `bin/rails db:migrate`. If your host already installed Solid Queue migrations manually, delete duplicate files before migrating.
5. **Wire Action Cable** if necessary. SourceMonitor defaults to Solid Cable; confirm `ApplicationCable::Connection`/`Channel` exist and that `config/initializers/source_monitor.rb` uses the adapter you expect. To switch to Redis, set `config.realtime.adapter = :redis` and `config.realtime.redis_url`.
6. **Start workers** with `bin/rails solid_queue:start` (or your process manager). The install generator automatically configures recurring jobs in `config/recurring.yml` for fetch scheduling, scraping, and cleanup. They'll run with `bin/dev` or `bin/jobs`.
   - **Procfile.dev:** The generator automatically patches `Procfile.dev` with a `jobs:` entry for Solid Queue. Verify the file contains `jobs: bundle exec rake solid_queue:start` after running the generator.
   - **Recurring schedule:** The generator automatically patches `config/queue.yml` dispatchers with `recurring_schedule: config/recurring.yml`. Verify the key is present after running the generator.
7. **Review the initializer** and tune queue names, HTTP timeouts, scraping adapters, retention limits, authentication hooks, and Mission Control integration. The [configuration reference](configuration.md) details every option.
8. **Verify the install**: run `bin/source_monitor verify` to ensure Solid Queue workers and Action Cable are healthy, then visit the mount path to trigger a fetch manually. Enable telemetry if you want JSON logs recorded for support.

### Host Compatibility Matrix

| Host Scenario | Status | Notes |
| --- | --- | --- |
| Rails 8 full-stack app | ✅ Supported | Use the guided workflow or the manual generator steps above |
| Rails 8 API-only app (`--api`) | ✅ Supported | Generator mounts engine; provide your own UI entry point if needed |
| Dedicated Solid Queue database | ✅ Supported | Run `bin/rails solid_queue:install` in the host app before copying SourceMonitor migrations |
| Redis-backed Action Cable | ✅ Supported | Set `config.realtime.adapter = :redis` and provide `config.realtime.redis_url`; existing `config/cable.yml` entries are preserved |

## Rollback Steps

If you need to revert the integration in a host app:

1. Remove `gem "source_monitor"` from the host Gemfile and rerun `bundle install`.
2. Delete the engine initializer (`config/initializers/source_monitor.rb`) and any navigation links referencing the mount path.
3. Remove the mount entry from `config/routes.rb` (the install generator adds a comment to help locate it).
4. Drop SourceMonitor tables if they are no longer needed:
   ```bash
   bin/rails db:migrate:down VERSION=<timestamp> # repeat for each engine migration
   ```
5. Remove Solid Queue / Solid Cable migrations only if no other components rely on them.

Document each removal in the host application's changelog to keep future upgrades predictable.

## Optional Devise System Test Template

Add a guardrail test in the host app (or dummy) to make sure authentication protects the dashboard after upgrades:

```ruby
# test/system/source_monitor_setup_test.rb
require "application_system_test_case"

class SourceMonitorSetupTest < ApplicationSystemTestCase
  test "signed in admin can reach SourceMonitor" do
    user = users(:admin)
    sign_in user

    visit "/source_monitor"
    assert_text "SourceMonitor Dashboard"
  end
end
```

- Swap `sign_in user` for your Devise helper (`login_as`, etc.).
- Use fixtures or factories that guarantee the user is authorized per the initializer’s `authorize_with` hook.

## Additional Notes

- Re-running `bin/source_monitor install` is idempotent: if migrations already exist or Devise hooks are present, the workflow skips creation and only re-verifies prerequisites.
- The CLI wraps the same services the rake tasks use, so CI can call `bin/source_monitor verify` directly after migrations to catch worker/cable misconfigurations before deploying.
- Keep this document aligned with the PRD (`tasks/prd-setup-workflow-streamlining.md`) and active task list (`tasks/tasks-setup-workflow-streamlining.md`).
