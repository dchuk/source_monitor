# Shipped Milestones

## default (2026-02-09 to 2026-02-10)

**Core value:** Drop-in Rails engine for feed monitoring, content scraping, and operational dashboards.

### Metrics

| Metric | Value |
|--------|-------|
| Phases | 4 |
| Plans completed | 14 |
| Commits | 18 |
| Requirements satisfied | 15/15 |
| Test runs | 841 (up from 473) |
| Coverage | 86.97% line (510 uncovered, down from 2117) |

### Phases

1. Coverage Analysis & Quick Wins (2 plans)
2. Critical Path Test Coverage (5 plans)
3. Large File Refactoring (4 plans)
4. Code Quality & Conventions Cleanup (3 plans)

### Archive

Location: `.vbw-planning/milestones/default/`
Tag: `milestone/default`

---

## upgrade-assurance (2026-02-12 to 2026-02-13)

**Goal:** Give host app developers confidence that gem updates go smoothly -- automated migration detection, upgrade command, config validation, and AI-assisted upgrade guidance.

### Metrics

| Metric | Value |
|--------|-------|
| Phases | 3 |
| Plans completed | 3 |
| Tasks completed | 14 |
| Commits | 12 |
| Requirements satisfied | 5/5 (REQ-26 through REQ-30) |
| Tests | 1003 (up from 973) |

### Phases

1. Upgrade Command & Migration Verifier (1 plan, 5 tasks)
2. Configuration Deprecation Framework (1 plan, 4 tasks)
3. Upgrade Skill & Documentation (1 plan, 5 tasks)

### Key Decisions

- 3 phases: command, config, skill -- each independently valuable
- `.source_monitor_version` marker file for version tracking
- Deprecation registry with :warning and :error severities
- sm-upgrade as a consumer skill (installed by default)

### Archive

Location: `.vbw-planning/milestones/upgrade-assurance/`
Tag: `milestone/upgrade-assurance`
