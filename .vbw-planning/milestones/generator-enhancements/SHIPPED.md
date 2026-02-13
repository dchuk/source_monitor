# Shipped: generator-enhancements

**Shipped:** 2026-02-12
**Tag:** milestone/generator-enhancements
**Release:** v0.4.0

## Summary

Made the install generator and verification suite catch the two most common host-app setup failures: missing Procfile.dev jobs entry and missing recurring_schedule dispatcher wiring. Also added dashboard UX improvements, Active Storage image downloads, and SSL certificate store configuration.

## Metrics

| Metric | Value |
|--------|-------|
| Phases | 7 (Phase 0-6) |
| Plans completed | 7 |
| Tasks completed | 34 |
| Commits | ~26 |
| Tests | 973 (up from 841) |
| New requirements satisfied | 10 (REQ-16 through REQ-25) |

## Phases

1. Phase 0: Documentation Gaps (quick fix)
2. Phase 1: Install Generator Steps (Procfile.dev + Queue Config)
3. Phase 2: Recurring Schedule Verifier
4. Phase 3: Skills & Documentation Alignment
5. Phase 4: Dashboard UX Improvements
6. Phase 5: Active Storage Image Downloads
7. Phase 6: Netflix Feed Investigation (SSL cert store fix)

## Key Decisions

- Docs-first approach: shipped doc fixes before code changes
- Always create/patch Procfile.dev for maximum hand-holding
- Target queue.yml only (Rails 8 default)
- External links open new tab with visual indicator icon
- Fetch log URL display: domain for RSS, item URL for scrapes
- Image downloads via background job to ItemContent (opt-in)
- SSL fix: general cert store config, not Netflix-specific
