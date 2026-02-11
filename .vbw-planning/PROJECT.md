<!-- VBW PROJECT TEMPLATE (ARTF-04) -- Human-facing project definition -->
<!-- Created by /vbw init, maintained by Architect agent -->

# SourceMonitor

## What This Is

SourceMonitor is a mountable Rails 8 engine for ingesting RSS/Atom/JSON feeds, scraping article content via pluggable adapters, and providing Solid Queue-powered dashboards for monitoring and remediation. It is distributed as a RubyGem and integrates with host Rails applications.

## Core Value

A drop-in Rails engine that gives any Rails application feed monitoring, content scraping, and operational dashboards without building the plumbing from scratch.

## Requirements

### Validated

None yet.

### Active

- [ ] Close test coverage gaps identified in the coverage baseline
- [ ] Refactor large files for maintainability and single-responsibility
- [ ] Ensure codebase follows Rails best practices and conventions throughout

### Out of Scope

- Multi-database support (MySQL/SQLite) -- Keep PostgreSQL-only for now
- Built-in authentication -- Continue relying on host app for auth

## Context

This is a brownfield Rails engine at v0.2.1 with 530 source files (325 Ruby, 48 ERB). The codebase has 130 test files, CI/CD via GitHub Actions, and a coverage baseline tracking 2329 lines of uncovered code. Key technical debt includes large files (FeedFetcher 627 lines, Configuration 655 lines, ImportSessionsController 792 lines) and coverage gaps in critical paths.

## Constraints

- **Ruby**: >= 3.4.0
- **Rails**: >= 8.0.3, < 9.0
- **Database**: PostgreSQL only
- **Testing**: Minitest (not RSpec), branch coverage via SimpleCov

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Focus on coverage + refactoring before new features | Stabilize existing code before adding complexity | Pending |
| Keep PostgreSQL-only | Not worth the complexity of multi-DB support at this stage | Confirmed |
| Keep host-app auth | Engine should be composable, not opinionated about auth | Confirmed |

---
*Last updated: 2026-02-09 after VBW bootstrap*
