# Host App Setup Checklist

Step-by-step checklist for integrating SourceMonitor into a host Rails application.

## Phase 1: Prerequisites

- [ ] **Ruby 3.4+** installed (`ruby -v`)
- [ ] **Rails 8.0+** host application (`bin/rails about`)
- [ ] **PostgreSQL 14+** running and accessible
- [ ] **Node.js 18+** installed (for Tailwind/esbuild assets)
- [ ] **Solid Queue** in host Gemfile (`gem "solid_queue"`)
- [ ] **Solid Cable** or Redis available for Action Cable

## Phase 2: Install the Gem

```bash
# Option A: Released version
bundle add source_monitor --version "~> 0.3.0"

# Option B: GitHub edge
# Add to Gemfile: gem "source_monitor", github: "dchuk/source_monitor"

bundle install
```

- [ ] Gem added to Gemfile
- [ ] `bundle install` succeeds

## Phase 3: Run the Generator

```bash
# Guided (recommended)
bin/source_monitor install

# Manual
bin/rails generate source_monitor:install --mount-path=/source_monitor
```

Verify after running:
- [ ] `config/routes.rb` contains `mount SourceMonitor::Engine, at: "/source_monitor"`
- [ ] `config/initializers/source_monitor.rb` exists
- [ ] `config/recurring.yml` contains SourceMonitor recurring job entries

## Phase 4: Database Setup

```bash
# Copy engine migrations to host
bin/rails railties:install:migrations FROM=source_monitor

# Apply all pending migrations
bin/rails db:migrate
```

- [ ] Engine migrations copied (check `db/migrate/` for `sourcemon_*` tables)
- [ ] `bin/rails db:migrate` succeeds
- [ ] Tables created: `sourcemon_sources`, `sourcemon_items`, `sourcemon_fetch_logs`, etc.

## Phase 5: Configure Authentication

Edit `config/initializers/source_monitor.rb`:

```ruby
SourceMonitor.configure do |config|
  # Devise example
  config.authentication.authenticate_with :authenticate_user!
  config.authentication.authorize_with ->(controller) {
    controller.current_user&.admin?
  }
  config.authentication.current_user_method = :current_user
  config.authentication.user_signed_in_method = :user_signed_in?
end
```

- [ ] Authentication hook configured
- [ ] Authorization hook configured (if needed)

## Phase 6: Configure Workers

The install generator automatically configures recurring jobs in `config/recurring.yml` (fetch scheduling, scrape scheduling, item cleanup, log cleanup). These run automatically with `bin/dev` or `bin/jobs`.

Ensure `config/solid_queue.yml` (or equivalent) includes the SourceMonitor queues:

```yaml
# config/solid_queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "source_monitor_fetch"
      threads: 2
      processes: 1
    - queues: "source_monitor_scrape"
      threads: 2
      processes: 1
```

```bash
bin/rails solid_queue:start
```

- [ ] Queue configuration includes `source_monitor_fetch` and `source_monitor_scrape`
- [ ] Workers started and processing

## Phase 7: Verify Installation

```bash
bin/source_monitor verify
```

- [ ] Verification passes (exit code 0)
- [ ] Dashboard loads at mount path (e.g., `http://localhost:3000/source_monitor`)
- [ ] Create a test source, trigger "Fetch Now", confirm items appear

## Phase 8: Optional Configuration

- [ ] HTTP client tuned (timeouts, proxy, retries)
- [ ] Fetching intervals configured for your workload
- [ ] Health thresholds adjusted
- [ ] Retention policy set
- [ ] Custom scraper adapters registered
- [ ] Event callbacks wired for host integration
- [ ] Realtime adapter confirmed (Solid Cable or Redis)
- [ ] Mission Control integration enabled (if desired)

## Troubleshooting

| Problem | Solution |
|---|---|
| `bin/source_monitor` not found | Run `bundle install`, ensure gem is loaded |
| Migrations fail | Check for duplicate Solid Queue migrations, remove dupes |
| Dashboard 404 | Verify mount in `config/routes.rb`, restart server |
| Jobs not processing | Start Solid Queue workers, check queue names match config |
| Action Cable errors | Verify Solid Cable or Redis is configured in `cable.yml` |
| Auth redirect loop | Check `authenticate_with` matches your auth system |

See `docs/troubleshooting.md` for comprehensive fixes.
