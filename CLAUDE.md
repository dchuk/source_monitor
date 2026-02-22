# SourceMonitor

**Core value:** Drop-in Rails engine for feed monitoring, content scraping, and operational dashboards.

## Active Context

**Milestone:** polish-and-reliability (extended)
**Phase:** 4 of 5 -- Bug Fixes & Polish (pending planning)
**Previous phases:** Backend Fixes, Favicon Support, Toast Stacking (all complete)
**Next action:** /vbw:vibe to plan and execute Phase 4

## Key Decisions

- Keep PostgreSQL-only for now
- Keep host-app auth model
- Ruby autoload for lib/ modules (not Zeitwerk)
- PG parallel fork segfault resolved: switched to thread-based parallelism in aia-ssl-fix milestone

## Installed Skills

- agent-browser (global)
- flowdeck (global)
- ralph-tui-create-json (global)
- ralph-tui-prd (global)
- vastai (global)
- find-skills (global)

## Learned Patterns

- Sub-module extraction: create `module/submodule.rb` with `require_relative`, lazy accessors, forwarding methods for backward compat
- Coverage runs need `COVERAGE=1 PARALLEL_WORKERS=1` with threads (not forks) to avoid PG segfault and SimpleCov data loss
- Test isolation: scope queries to specific source/item to prevent cross-test contamination in parallel runs
- RuboCop omakase: only 45/775 cops enabled, all Metrics cops disabled -- no file size enforcement

## VBW Commands

This project uses VBW (Vibe Better with Claude Code).
Run /vbw:status for current progress.
Run /vbw:help for all commands.

---

# Rails Development Conventions

## Tech Stack

| Layer | Technology |
|-------|------------|
| Ruby | 4.0+ |
| Rails | 8.x |
| Testing | Minitest (no fixtures -- uses factory helpers + WebMock/VCR) |
| Authorization | Host app responsibility (mountable engine) |
| Jobs | Solid Queue |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS |
| Linting | RuboCop (omakase) + Brakeman |
| Database | PostgreSQL only |

## Architecture Conventions

### Models First
- Business logic lives in models. Use concerns for horizontal sharing.
- Service objects ONLY for operations spanning 3+ models or external integrations.
- Query objects for complex queries that don't fit a single scope.
- Presenters (SimpleDelegator) for view-specific formatting.

### Everything-is-CRUD Routing
- Prefer creating a new resource over adding custom actions.
- `POST /posts/:id/publications` over `POST /posts/:id/publish`.
- RESTful routes only; no `member` or `collection` blocks with custom verbs.

### State as Records
- Track business state transitions as separate records (who/when/why).
- Boolean columns ONLY for technical flags (e.g., `email_verified`).

### Jobs
- Shallow jobs: call `_later` or `_now` methods on models/services.
- Jobs contain only deserialization + delegation. No business logic.
- Use Solid Queue recurring jobs for scheduled work.

### Frontend
- Turbo Frames for partial page updates.
- Turbo Streams for real-time broadcasts.
- Stimulus controllers: small, focused, one behavior each.
- Tailwind CSS utility classes; extract components for repeated patterns.

## Testing Conventions

- **Framework:** Minitest. NEVER use RSpec or FactoryBot.
- **Helpers:** `create_source!` factory, `with_inline_jobs`, `with_queue_adapter`.
- **HTTP:** WebMock disables external HTTP; VCR for recorded cassettes.
- **Config:** Reset every test with `SourceMonitor.reset_configuration!`.
- **TDD workflow:** Red (failing test) -> Green (minimal pass) -> Refactor.
- **Coverage:** Every model validation, scope, and public method. Every controller action.

## Quality Gates

- `bin/rubocop` -- zero offenses before commit.
- `bin/brakeman --no-pager` -- zero warnings before merge.
- `bin/rails test` -- all tests pass.
- `yarn build` -- rebuild JS assets if any `.js` files changed (ESLint runs in CI).
- No N+1 queries (use `includes`/`preload`).
- No hardcoded credentials (use Rails credentials or ENV).

### Pre-Push CI Checklist (run ALL before pushing to GitHub)

Before pushing any branch (especially release branches), run the full CI equivalent locally:

1. `bin/rubocop` -- catches Ruby lint issues
2. `PARALLEL_WORKERS=1 bin/rails test` -- catches test failures AND diff coverage gaps
3. `bin/brakeman --no-pager` -- catches security issues
4. `yarn build` -- rebuilds JS and catches ESLint issues (CI runs ESLint separately)

**Why:** CI failures cost ~5 min per round-trip. In v0.8.0, skipping ESLint and diff coverage checks locally caused 2 wasted CI cycles. Common blind spots:
- JS files need `/* global */` declarations for browser APIs (MutationObserver, requestAnimationFrame, etc.)
- Every `rescue` / fallback / error path in new source code needs test coverage (CI diff coverage gate rejects uncovered lines)
- `yarn build` must run after JS changes to sync sourcemaps

## QA and UAT Rules

- **Browser-first verification:** During VBW QA (`/vbw:qa`) and UAT (`/vbw:verify`), ALWAYS start by using `agent-browser` to test UI scenarios yourself before presenting checkpoints to the user. Navigate to the dummy app (port 3002), take snapshots/screenshots, and verify visual and functional behavior with agents first.
- **Automate what you can:** Any test that can be verified programmatically (config defaults, job enqueue behavior, controller responses) should be automated -- only present truly visual/interactive tests to the user.
- **Dummy app port:** The SourceMonitor dummy app runs on port 3002 (`cd test/dummy && bin/rails server -p 3002`).

## Security Rules

### Protected Files (NEVER read or output)
- `.env`, `.env.*`
- `config/master.key`, `config/credentials.yml.enc`
- `.kamal/secrets`
- Any `*.pem`, `*.key` files

### Forbidden Operations
- `git push --force` to main/master/production
- `git reset --hard` without explicit user confirmation
- `rm -rf` on root, home, or parent directories
- `chmod 777`

## Development Commands

```bash
bin/dev                     # Start dev server
bin/rails test              # Run all tests
bin/rubocop                 # Check style
bin/rubocop -a              # Auto-fix style
bin/brakeman --no-pager     # Security scan
bin/rails db:migrate        # Run migrations
```

## Agent Catalog

These agents are available in `.claude/agents/`:

| Agent | Trigger |
|-------|---------|
| `rails-model` | Creating/modifying models, concerns, validations, scopes |
| `rails-controller` | Creating/modifying controllers, routes, CRUD actions |
| `rails-concern` | Extracting shared behavior into concerns |
| `rails-state-records` | Implementing state-as-records pattern |
| `rails-service` | Service objects for multi-model operations |
| `rails-query` | Query objects for complex database queries |
| `rails-presenter` | Presenters for view formatting logic |
| `rails-policy` | Pundit authorization policies |
| `rails-view-component` | ViewComponents with previews |
| `rails-migration` | Safe, reversible database migrations |
| `rails-test` | Writing minitest tests |
| `rails-tdd` | TDD red-green-refactor workflow |
| `rails-job` | Background jobs with Solid Queue |
| `rails-mailer` | ActionMailer with previews |
| `rails-hotwire` | Turbo Frames/Streams + Stimulus + Tailwind |
| `rails-review` | Code review + security audit (read-only) |
| `rails-lint` | RuboCop + Brakeman fixes |
| `rails-implement` | Implementation orchestrator |

## Skill Catalog

These skills are available in `.claude/skills/`:

| Skill | Purpose |
|-------|---------|
| `rails-architecture` | Architecture decision rubric and patterns |
| `rails-model-generator` | Model generation with conventions |
| `rails-controller` | Controller patterns and integration tests |
| `rails-concern` | Concern extraction patterns |
| `rails-service-object` | Service object with Result pattern |
| `rails-query-object` | Query object patterns |
| `rails-presenter` | Presenter patterns |
| `form-object-patterns` | Form objects for complex forms |
| `viewcomponent-patterns` | ViewComponent patterns and testing |
| `authentication-flow` | Authentication implementation |
| `authorization-pundit` | Pundit policy patterns |
| `database-migrations` | Safe migration patterns |
| `caching-strategies` | Fragment, HTTP, and Russian-doll caching |
| `solid-queue-setup` | Solid Queue configuration |
| `hotwire-patterns` | Turbo + Stimulus + Tailwind patterns |
| `action-cable-patterns` | WebSocket patterns |
| `action-mailer-patterns` | Email patterns with previews |
| `api-versioning` | API versioning strategies |
| `tdd-cycle` | TDD workflow for minitest |
| `performance-optimization` | Performance tuning patterns |
| `i18n-patterns` | Internationalization patterns |
| `active-storage-setup` | Active Storage configuration |

## Source Monitor Skills

Engine-specific skills (`sm-*` prefix). Consumer skills install by default; contributor skills are opt-in.

### Consumer Skills (default install)

| Skill | Purpose |
|-------|---------|
| `sm-host-setup` | Full host app setup walkthrough |
| `sm-configure` | DSL configuration across all sub-sections |
| `sm-scraper-adapter` | Custom scraper inheriting `Scrapers::Base` |
| `sm-event-handler` | Lifecycle callbacks (after_item_created, etc.) |
| `sm-model-extension` | Extend engine models from host app |
| `sm-dashboard-widget` | Dashboard queries, presenters, Turbo broadcasts |
| `sm-upgrade` | Gem upgrade workflow with CHANGELOG parsing |

### Contributor Skills (opt-in)

| Skill | Purpose |
|-------|---------|
| `sm-domain-model` | Model graph, relationships, state values, scopes |
| `sm-architecture` | Module map, autoload tree, extraction patterns |
| `sm-engine-test` | Engine test helpers, VCR/WebMock, parallel caveats |
| `sm-configuration-setting` | Add settings to config sub-sections |
| `sm-pipeline-stage` | Add/modify fetch or scrape pipeline stages |
| `sm-engine-migration` | Migrations with `sourcemon_` prefix conventions |
| `sm-job` | Solid Queue jobs with shallow delegation |
| `sm-health-rule` | Health status rules, circuit breaker, auto-pause |

### Skills Distribution

Host apps can install `sm-*` skills via rake:

```bash
bin/rails source_monitor:skills:install        # Consumer skills (default)
bin/rails source_monitor:skills:contributor     # Contributor skills
bin/rails source_monitor:skills:all            # All skills
bin/rails source_monitor:skills:remove         # Remove all sm-* skills
```

## Maintenance Rules

- **Skills & docs alignment**: Whenever engine code changes (models, configuration, pipeline, jobs, migrations, scrapers, events, health rules, or dashboard), the corresponding `sm-*` skill and its `reference/` files MUST be updated in the same PR to ensure skills always reflect current engine behavior.
