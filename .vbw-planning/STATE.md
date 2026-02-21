# State

## Current Position

- **Milestone:** polish-and-reliability
- **Phase:** 3 -- Toast Stacking
- **Status:** Complete
- **Progress:** 100%
- **Plans:** 1 (1/1 complete)

## Decisions

| Decision | Date | Context |
|----------|------|---------|
| Active Storage for favicons | 2026-02-20 | has_one_attached with guard, consistent with ItemContent pattern |
| Smarter scrape limit | 2026-02-20 | Count only running jobs, not queued; keeps safety but removes false bottleneck |
| Browser-like default UA | 2026-02-20 | Simple global fix for bot-blocked feeds like Uber |
| Health check triggers status update | 2026-02-20 | Successful manual health check should transition declining -> improving |
| Toast cap + hover expand | 2026-02-20 | Max 3 visible, +N more badge, hover to see all |

## Todos

## Metrics

- **Started:** 2026-02-20
- **Phases:** 3
- **Tests at start:** 1033

## Blockers
None
