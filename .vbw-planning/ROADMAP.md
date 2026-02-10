<!-- VBW ROADMAP TEMPLATE (ARTF-07) -- Phase-based project roadmap -->
<!-- Created by Architect agent during /vbw scope -->

# SourceMonitor Roadmap

## Overview

This roadmap focuses on stabilizing and improving the existing SourceMonitor codebase through test coverage improvements and refactoring for maintainability. 4 phases progressing from analysis to coverage to refactoring to cleanup.

## Phases

- [x] Phase 1: Coverage Analysis & Quick Wins
- [x] Phase 2: Critical Path Test Coverage
- [x] Phase 3: Large File Refactoring
- [ ] Phase 4: Code Quality & Conventions Cleanup

## Phase Details

### Phase 1: Coverage Analysis & Quick Wins

**Goal:** Analyze the coverage baseline, identify the highest-impact gaps, and close easy coverage wins (frozen_string_literal, small utility classes).
**Depends on:** None

**Requirements:**
- REQ-13: Frozen string literal consistency
- REQ-14: RuboCop audit

**Success Criteria:**
1. All Ruby files have frozen_string_literal: true
2. Zero RuboCop violations against omakase ruleset
3. Coverage baseline shrinks by at least 10%

**Plans:**
- [x] Plan 01: frozen-string-literal-audit (5f02db8)
- [x] Plan 02: rubocop-audit-and-fix (no changes needed)

### Phase 2: Critical Path Test Coverage

**Goal:** Close the major test coverage gaps in the most critical business logic -- feed fetching, item creation, configuration, dashboard queries, and broadcasting.
**Depends on:** Phase 1

**Requirements:**
- REQ-01: FeedFetcher coverage
- REQ-02: ItemCreator coverage
- REQ-03: Configuration coverage
- REQ-04: Dashboard::Queries coverage
- REQ-05: Broadcaster coverage
- REQ-06: BulkSourceScraper coverage
- REQ-07: SourcesIndexMetrics coverage

**Success Criteria:**
1. Coverage baseline shrinks by at least 50% from original
2. All critical path files have branch coverage above 80%
3. CI pipeline passes with no regressions

**Plans:**
- [x] Plan 01: feed-fetcher-tests (8d4e8d3)
- [x] Plan 02: item-creator-tests (ce8ede4)
- [x] Plan 03: configuration-tests (66b8df2)
- [x] Plan 04: dashboard-and-analytics-tests (a8f2611, 2e50580)
- [x] Plan 05: scraping-and-broadcasting-tests (e497891, 66b8df2)

### Phase 3: Large File Refactoring

**Goal:** Break down the three largest files (FeedFetcher, Configuration, ImportSessionsController) into focused, single-responsibility modules while maintaining all existing tests.
**Depends on:** Phase 2

**Requirements:**
- REQ-08: Extract FeedFetcher
- REQ-09: Extract Configuration
- REQ-10: Extract ImportSessionsController
- REQ-11: Fix LogEntry table name
- REQ-12: Replace eager requires with autoloading

**Success Criteria:**
1. No single file exceeds 300 lines
2. All existing tests pass without modification (or with minimal adapter changes)
3. Public API remains unchanged

**Plans:**
- [x] Plan 01: extract-feed-fetcher (2f00274)
- [x] Plan 02: extract-configuration-settings (ab823a3)
- [x] Plan 03: extract-import-sessions-controller (9dce996)
- [x] Plan 04: fix-log-entry-and-autoloading (fb99d3d)

### Phase 4: Code Quality & Conventions Cleanup

**Goal:** Final pass to ensure all code follows Rails best practices and conventions, clean up any remaining debt.
**Depends on:** Phase 3

**Requirements:**
- REQ-15: Rails conventions audit

**Success Criteria:**
1. All models, controllers, and service objects follow established conventions
2. No RuboCop violations
3. Coverage baseline is at least 60% smaller than original
4. CI pipeline fully green

**Plans:**
- [ ] Plan 01: conventions-audit
- [ ] Plan 02: final-cleanup

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|---------------|--------|-----------|
| 1 - Coverage Analysis & Quick Wins | 2/2 | complete | 2026-02-09 |
| 2 - Critical Path Test Coverage | 5/5 | complete | 2026-02-09 |
| 3 - Large File Refactoring | 4/4 | complete | 2026-02-10 |
| 4 - Code Quality & Conventions Cleanup | 0/2 | pending | -- |

---
*Last updated: 2026-02-10 after Phase 3 completion*
