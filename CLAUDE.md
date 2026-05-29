# SourceMonitor

**Core value:** Drop-in Rails engine for feed monitoring, content scraping, and operational dashboards.

> **Engine conventions live in [`AGENTS.md`](AGENTS.md)** — the canonical, cross-agent reference for tech stack, architecture, testing, quality gates, the pre-push CI checklist, security rules, configuration DSL, and commands. This file holds only Claude Code-specific context: working memory, VBW commands, and the `.claude/` agent/skill catalogs. When a convention changes, edit `AGENTS.md`, not here.

## Active Context

**Last shipped:** rails-audit-and-refactoring (7 phases, 30 plans)
**Next action:** /vbw:vibe to start new work

## Key Decisions

- Keep PostgreSQL-only for now
- Keep host-app auth model (fail-closed by default since #129)
- Ruby autoload for lib/ modules (not Zeitwerk)
- PG parallel fork segfault resolved: switched to thread-based parallelism in aia-ssl-fix milestone

## Installed Skills

- agent-browser (global)
- flowdeck (global)
- ralph-tui-create-json (global)
- ralph-tui-prd (global)
- vastai (global)
- find-skills (global)

## VBW Commands

This project uses VBW (Vibe Better with Claude Code).
Run /vbw:status for current progress.
Run /vbw:help for all commands.

---

## QA and UAT Rules (Claude Code)

- **Browser-first verification:** During VBW QA (`/vbw:qa`) and UAT (`/vbw:verify`), ALWAYS start by using `agent-browser` to test UI scenarios yourself before presenting checkpoints to the user. Navigate to the dummy app (port 3002), take snapshots/screenshots, and verify visual and functional behavior with agents first.
- **Automate what you can:** anything verifiable programmatically should be a test — see the Testing section in [`AGENTS.md`](AGENTS.md) — and only present truly visual/interactive checks to the user.

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

Engine-specific skills (`sm-*` prefix). Consumer skills install by default; contributor skills are opt-in. The **Skills & Docs Alignment** maintenance rule lives in [`AGENTS.md`](AGENTS.md).

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
