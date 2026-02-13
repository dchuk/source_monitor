<!-- VBW STATE -- Current milestone progress -->

# State

**Milestone:** generator-enhancements
**Current Phase:** All phases complete
**Status:** Ready for archive
**Date:** 2026-02-12

## Progress

- Phase 0: Complete (quick fix ea788ea)
- Phase 1: Complete (1 plan, 5 tasks, 4 commits)
- Phase 2: Complete (1 plan, 5 tasks, 1 commit)
- Phase 3: Complete (1 plan, 5 tasks, 1 commit) -- QA PASS
- Phase 4: Complete (1 plan, 5 tasks, 5 commits) -- QA PASS 23/23
- Phase 5: Complete (2 plans, 9 tasks, 9 commits) -- QA PASS 34/34
- Phase 6: Complete (1 plan, 5 tasks, 5 commits) -- QA PASS 18/18

## Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Docs-first approach | 2026-02-11 | Shipped doc fixes before code changes to unblock users immediately |
| 3 phases for code changes | 2026-02-11 | Generator steps, verification, then docs alignment -- each independently testable |
| Always create/patch Procfile.dev | 2026-02-11 | Maximum hand-holding for host app setup |
| Target queue.yml only | 2026-02-11 | Rails 8 default, no legacy naming support |
| External links open new tab with icon | 2026-02-12 | Consistent UX for all external URLs across dashboard, logs, sources, items |
| Fetch log URL display: domain for RSS, item URL for scrapes | 2026-02-12 | User requested contextual URL display based on event type |
| Image downloads via background job to ItemContent | 2026-02-12 | Content images only, opt-in via config.images.download_to_active_storage |
| SSL fix: general cert store config, not Netflix-specific | 2026-02-12 | OpenSSL::X509::Store#set_default_paths on every Faraday connection |

## Metrics

| Metric | Value |
|--------|-------|
| Phases | 7 (Phase 0-6) |
| Plans completed | 7 (across all phases) |
| Tasks completed | 34 |
| Commits | ~26 |
| Tests | 973 (up from 841) |
| RuboCop | 389 files, 0 offenses |
| Brakeman | 0 warnings |
