<!-- VBW ROADMAP -- Phase decomposition with requirement mapping -->
<!-- Created during /vbw scope -->

# SourceMonitor Upgrade Assurance Roadmap

**Milestone:** upgrade-assurance
**Goal:** Give host app developers confidence that gem updates go smoothly -- automated migration detection, upgrade command, config validation, and AI-assisted upgrade guidance.

## Phases

1. [x] Phase 1: Upgrade Command & Migration Verifier
2. [x] Phase 2: Configuration Deprecation Framework
3. [x] Phase 3: Upgrade Skill & Documentation

## Phase Details

### Phase 1: Upgrade Command & Migration Verifier

**Goal:** Add `bin/source_monitor upgrade` that detects version changes since last install, copies new migrations, re-runs the idempotent generator, runs verification, and reports what changed. Also add a `PendingMigrationsVerifier` to the existing verification suite.

**Requirements:** REQ-26, REQ-27

**Success Criteria:**
- `bin/source_monitor upgrade` compares stored version marker against `SourceMonitor::VERSION`
- If version changed: copies new migrations, re-runs generator, runs `bin/source_monitor verify`
- If no version change: reports "Already up to date" with current version
- `PendingMigrationsVerifier` checks `db:migrate:status` for unmigrated SourceMonitor migrations
- Verifier integrated into `bin/source_monitor verify` and the upgrade flow
- Version marker stored in host app (e.g., `.source_monitor_version` or DB-backed)
- `bin/rails test` passes, RuboCop clean

### Phase 2: Configuration Deprecation Framework

**Goal:** Add a lightweight framework that warns host app developers when their initializer uses config options that have been renamed, removed, or have changed defaults. Warnings appear at boot time via Rails logger.

**Requirements:** REQ-28

**Success Criteria:**
- Engine maintains a deprecation registry (option name, version deprecated, replacement if any)
- At configuration load time, deprecated option usage triggers a Rails.logger.warn with actionable message
- Removed options that are still referenced raise a clear error with migration path
- Framework is opt-in for engine developers (simple DSL to register deprecations)
- Zero false positives on current valid configuration
- `bin/rails test` passes, RuboCop clean

### Phase 3: Upgrade Skill & Documentation

**Goal:** Create an `sm-upgrade` AI skill that guides agents through post-update workflows, and write a versioned upgrade guide for human developers.

**Requirements:** REQ-29, REQ-30

**Success Criteria:**
- `sm-upgrade` skill covers: reading CHANGELOG between versions, running upgrade command, interpreting results, handling edge cases
- Skill references the upgrade command and verification suite
- `docs/upgrade.md` includes: general upgrade steps, version-specific notes (0.3.x → 0.4.x), troubleshooting
- Skills installer updated to include `sm-upgrade` in consumer set
- Existing `sm-host-setup` skill cross-references upgrade flow

## Progress

| Phase | Status | Plans |
|-------|--------|-------|
| 1 | Complete | PLAN-01 (5 tasks, 5 commits) |
| 2 | Complete | PLAN-01 (4 tasks, 3 commits) |
| 3 | Complete | PLAN-01 (5 tasks, 4 commits) |

## Requirement Mapping

| REQ | Phase | Description |
|-----|-------|-------------|
| REQ-26 | 1 | Upgrade command with version detection and auto-remediation |
| REQ-27 | 1 | PendingMigrationsVerifier in verification suite |
| REQ-28 | 2 | Config deprecation framework with boot-time warnings |
| REQ-29 | 3 | sm-upgrade AI skill for agent-guided updates |
| REQ-30 | 3 | Upgrade guide documentation |
