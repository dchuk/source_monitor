<!-- VBW REQUIREMENTS TEMPLATE (ARTF-06) -- Structured requirements with traceability -->
<!-- Created by Architect agent during /vbw scope -->

# SourceMonitor Requirements

Defined: 2026-02-09
Core value: Drop-in Rails engine for feed monitoring, content scraping, and operational dashboards.

## v1 Requirements

### Test Coverage

- [ ] **REQ-01**: Close coverage gaps in `FeedFetcher` -- add tests for uncovered branches in the fetch pipeline
- [ ] **REQ-02**: Close coverage gaps in `ItemCreator` -- add tests for item creation edge cases
- [ ] **REQ-03**: Close coverage gaps in `Configuration` -- test nested settings classes and edge cases
- [ ] **REQ-04**: Close coverage gaps in `Dashboard::Queries` -- test dashboard query logic
- [ ] **REQ-05**: Close coverage gaps in `Broadcaster` -- test realtime broadcasting logic
- [ ] **REQ-06**: Close coverage gaps in `BulkSourceScraper` -- test bulk scraping workflows
- [ ] **REQ-07**: Close coverage gaps in `SourcesIndexMetrics` -- test analytics calculations

### Refactoring

- [ ] **REQ-08**: Extract `FeedFetcher` (627 lines) into focused single-responsibility classes
- [ ] **REQ-09**: Extract `Configuration` (655 lines) nested settings classes into separate files
- [ ] **REQ-10**: Extract `ImportSessionsController` (792 lines) wizard steps into step-specific concerns or service objects
- [ ] **REQ-11**: Fix `LogEntry` hard-coded table name to use configurable prefix system
- [ ] **REQ-12**: Replace eager 102+ require statements in `lib/source_monitor.rb` with autoloading

### Code Quality

- [ ] **REQ-13**: Ensure frozen_string_literal is consistent across all Ruby files
- [ ] **REQ-14**: Audit and fix any RuboCop violations against omakase ruleset
- [ ] **REQ-15**: Ensure all models, controllers, and service objects follow Rails conventions

### Generator Enhancements

- [ ] **REQ-16**: Install generator patches `Procfile.dev` with a `jobs:` entry for Solid Queue
- [ ] **REQ-17**: Install generator patches queue config dispatcher with `recurring_schedule: config/recurring.yml`
- [ ] **REQ-18**: Guided workflow (`Setup::Workflow`) integrates both new generator steps
- [ ] **REQ-19**: `RecurringScheduleVerifier` checks that recurring tasks are registered with Solid Queue
- [ ] **REQ-20**: `SolidQueueVerifier` remediation suggests `Procfile.dev` when workers not detected
- [ ] **REQ-21**: Skills and documentation updated to reflect automated Procfile.dev and recurring_schedule setup

### Dashboard UX

- [ ] **REQ-22**: Fetch logs show source URL for both success and failure entries on the dashboard
- [ ] **REQ-23**: Dashboard links to sources and items are clickable and open in a new tab

### Active Storage Image Downloads

- [ ] **REQ-24**: Configurable option to download inline images from items to Active Storage instead of loading from source

### Feed Compatibility

- [ ] **REQ-25**: Investigate and fix failing fetch for Netflix Tech Blog feed (https://netflixtechblog.com/feed)

### Upgrade Assurance

- [ ] **REQ-26**: `bin/source_monitor upgrade` command detects version changes, copies new migrations, re-runs generator, and runs verification
- [ ] **REQ-27**: `PendingMigrationsVerifier` checks for unmigrated SourceMonitor tables in the verification suite
- [ ] **REQ-28**: Configuration deprecation framework warns on stale, renamed, or removed initializer options at boot time
- [ ] **REQ-29**: `sm-upgrade` AI skill teaches agents how to handle gem updates with CHANGELOG parsing and step-by-step guidance
- [ ] **REQ-30**: Upgrade guide documentation (`docs/upgrade.md`) with version-specific instructions

## v2 Requirements

- [ ] **REQ-XX**: Improve optional dependency loading with clear error messages
- [ ] **REQ-XX**: Add database index verification tooling
- [ ] **REQ-XX**: Document health check endpoint response format

## Out of Scope

| Item | Reason |
|------|--------|
| Multi-database support (MySQL/SQLite) | PostgreSQL-only simplifies development |
| Built-in authentication | Host app responsibility |

## Traceability

Requirement-to-phase mapping is tracked in ROADMAP.md.
