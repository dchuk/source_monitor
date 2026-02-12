---
name: sm-host-setup
description: Use when setting up SourceMonitor in a host Rails application, including gem installation, engine mounting, migration copying, initializer creation, and verifying the install works.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# sm-host-setup: Host Application Setup

Guides integration of the SourceMonitor engine into a host Rails application.

## When to Use

- Adding SourceMonitor to a new or existing Rails 8 host app
- Troubleshooting a broken installation
- Re-running setup after upgrading the gem
- Rolling back the engine from a host app

## Prerequisites

| Requirement | Minimum | How to Check |
|---|---|---|
| Ruby | 3.4+ | `ruby -v` |
| Rails | 8.0+ | `bin/rails about` |
| PostgreSQL | 14+ | `psql --version` |
| Node.js | 18+ | `node -v` |
| Solid Queue | >= 0.3, < 3.0 | Check host Gemfile |
| Solid Cable or Redis | Solid Cable >= 3.0 | Check host Gemfile |

## Installation Methods

### Method 1: Guided CLI (Recommended)

The engine ships a guided installer that handles every step interactively.

```bash
# From the host app root:
bundle add source_monitor --version "~> 0.3.0"
bundle install
bin/source_monitor install
```

The guided workflow:
1. Checks prerequisites via `DependencyChecker`
2. Prompts for mount path (default: `/source_monitor`)
3. Ensures `gem "source_monitor"` in Gemfile, runs `bundle install`
4. Runs `npm install` if `package.json` exists
5. Executes `bin/rails generate source_monitor:install --mount-path=...`
6. Copies and deduplicates migrations, runs `bin/rails db:migrate`
7. Patches the initializer with navigation hint and optional Devise hooks
8. Runs verification and prints a report

Non-interactive mode:
```bash
bin/source_monitor install --yes
```

### Method 2: Manual Step-by-Step

```bash
# 1. Add the gem
gem "source_monitor", "~> 0.3.0"  # in Gemfile
bundle install

# 2. Run the install generator (mounts engine, creates initializer, configures recurring jobs)
bin/rails generate source_monitor:install --mount-path=/source_monitor

# 3. Copy engine migrations
bin/rails railties:install:migrations FROM=source_monitor

# 4. Apply migrations
bin/rails db:migrate

# 5. Start background workers (recurring jobs configured automatically in config/recurring.yml)
bin/rails solid_queue:start

# Note: The generator automatically patches Procfile.dev with a jobs: entry
# and adds recurring_schedule to your queue.yml dispatcher config.
# Re-run the generator if these were not applied: bin/rails generate source_monitor:install

# 6. Verify
bin/source_monitor verify
```

### Method 3: GitHub Edge

```ruby
# Gemfile
gem "source_monitor", github: "dchuk/source_monitor"
```

## What the Install Generator Does

The generator (`SourceMonitor::Generators::InstallGenerator`) performs five actions:

1. **Mounts the engine** in `config/routes.rb`:
   ```ruby
   mount SourceMonitor::Engine, at: "/source_monitor"
   ```
   Skips if already mounted. The mount path is configurable via `--mount-path`.

2. **Creates the initializer** at `config/initializers/source_monitor.rb`:
   Uses the template at `lib/generators/source_monitor/install/templates/source_monitor.rb.tt`. Skips if the file already exists.

3. **Configures recurring jobs** in `config/recurring.yml`:
   Adds entries for `ScheduleFetchesJob` (every minute), scrape scheduling (every 2 minutes), `ItemCleanupJob` (2am daily), and `LogCleanupJob` (3am daily). If the file doesn't exist, creates it with `default: &default` and environment sections. If it exists, merges entries without overwriting. Skips if SourceMonitor entries are already present.

4. **Patches Procfile.dev** with a `jobs:` entry for Solid Queue:
   Creates the file with `web:` and `jobs:` entries if it does not exist. Appends a `jobs:` entry if the file exists but lacks one. Skips if a `jobs:` entry is already present.

5. **Patches queue.yml dispatcher** with `recurring_schedule: config/recurring.yml`:
   Adds the `recurring_schedule` key to each dispatcher entry in `config/queue.yml`. If no dispatchers section exists, creates a default one. Skips if `recurring_schedule` is already configured. Skips if `config/queue.yml` does not exist.

Re-running the generator is safe and idempotent.

## Post-Install Configuration

After installation, review and customize the initializer. Key areas:

| Section | Purpose |
|---|---|
| Queue settings | Queue names, concurrency, namespace |
| Authentication | `authenticate_with`, `authorize_with` hooks |
| HTTP client | Timeouts, proxy, retries |
| Fetching | Adaptive scheduling intervals and factors |
| Health | Auto-pause/resume thresholds |
| Scrapers | Register custom scraper adapters |
| Retention | Item age limits and pruning strategy |
| Events | Lifecycle callbacks for integration |
| Models | Table prefix, concerns, validations |
| Realtime | Action Cable adapter (Solid Cable/Redis) |

See the `sm-configure` skill for full configuration reference.

## Verification

```bash
# CLI verification
bin/source_monitor verify

# Rake task verification
bin/rails source_monitor:setup:verify

# Prerequisite check only
bin/rails source_monitor:setup:check
```

Verification checks Solid Queue workers and Action Cable health. Non-zero exit on failure.

Enable telemetry logging:
```bash
SOURCE_MONITOR_SETUP_TELEMETRY=true bin/source_monitor verify
# Logs to log/source_monitor_setup.log
```

## Devise Integration

When Devise is detected, the guided installer offers to wire authentication hooks:

```ruby
config.authentication.authenticate_with :authenticate_user!
config.authentication.authorize_with ->(controller) {
  controller.current_user&.respond_to?(:admin?) ? controller.current_user.admin? : true
}
config.authentication.current_user_method = :current_user
config.authentication.user_signed_in_method = :user_signed_in?
```

## Rollback

1. Remove `gem "source_monitor"` from Gemfile, `bundle install`
2. Delete `config/initializers/source_monitor.rb`
3. Remove `mount SourceMonitor::Engine` from `config/routes.rb`
4. Drop tables: `bin/rails db:migrate:down VERSION=<timestamp>` for each engine migration
5. Remove Solid Queue/Cable migrations only if no other components need them

## Host Compatibility

| Scenario | Status |
|---|---|
| Rails 8 full-stack app | Supported |
| Rails 8 API-only app | Supported |
| Dedicated Solid Queue database | Supported |
| Redis-backed Action Cable | Supported |

## Key Source Files

| File | Purpose |
|---|---|
| `lib/source_monitor/setup/workflow.rb` | Guided installer orchestration |
| `lib/generators/source_monitor/install/install_generator.rb` | Rails generator |
| `lib/generators/source_monitor/install/templates/source_monitor.rb.tt` | Initializer template |
| `lib/source_monitor/setup/initializer_patcher.rb` | Post-install patching |
| `lib/source_monitor/setup/procfile_patcher.rb` | Procfile.dev patching for guided workflow |
| `lib/source_monitor/setup/queue_config_patcher.rb` | Queue config patching for guided workflow |
| `lib/source_monitor/setup/verification/runner.rb` | Verification runner |
| `lib/source_monitor/engine.rb` | Engine configuration and initializers |
| `docs/setup.md` | Full setup documentation |
| `docs/troubleshooting.md` | Common fixes |

## References

- `docs/setup.md` -- Complete setup workflow documentation
- `docs/configuration.md` -- Configuration reference
- `docs/troubleshooting.md` -- Common issues and fixes

## Testing

After setup, verify with:
1. `bin/source_monitor verify` -- Checks Solid Queue and Action Cable
2. Visit the mount path in browser -- Dashboard should load
3. Create a source and trigger "Fetch Now" -- Validates end-to-end

Optional system test for host apps using Devise:
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

## Checklist

- [ ] Ruby 3.4+, Rails 8.0+, PostgreSQL 14+ available
- [ ] `gem "source_monitor"` added to Gemfile
- [ ] `bundle install` completed
- [ ] Install generator ran (`bin/rails generate source_monitor:install`)
- [ ] Engine migrations copied and applied
- [ ] Recurring jobs configured in `config/recurring.yml`
- [x] `Procfile.dev` includes `jobs:` entry for Solid Queue (handled by generator)
- [x] Dispatcher config includes `recurring_schedule: config/recurring.yml` (handled by generator)
- [ ] Solid Queue workers started
- [ ] Authentication hooks configured in initializer
- [ ] `bin/source_monitor verify` passes
- [ ] Dashboard accessible at mount path
