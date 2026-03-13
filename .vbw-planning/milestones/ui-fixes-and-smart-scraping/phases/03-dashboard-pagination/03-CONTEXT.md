# Phase 03: Dashboard Pagination — Context

Gathered: 2026-03-07
Calibration: architect

## Phase Boundary

Add pagination or grouping to the dashboard sources list and improve sources index pagination UX to handle large numbers of sources (100+) without overwhelming the page.

## Decisions

### Dashboard vs Sources Scope
- Both pages need work — the dashboard overview (/) AND the sources index (/sources)
- Sources index already has basic pagination (25/page, prev/next) but needs UX improvements
- Dashboard's UpcomingFetchSchedule loads ALL active sources into memory — needs DB-level scaling

### Grouping Strategy
- Dashboard: keep current fetch schedule grouping (0-30 min, 30-60 min, etc.), always expanded
- No collapsible sections — keep it simple, pagination handles length
- Sources index: flat table with existing sort/filter (no grouping change needed)

### Dashboard Schedule Scaling
- Move from in-memory Ruby grouping to ActiveRecord scopes per fetch window bucket
- Each fetch window bucket (0-30, 30-60, 60-120, 120-240, 240+) is a separate paginated section
- Use AR scopes with `where(next_fetch_at: range)` instead of raw SQL where possible
- Each section gets independent pagination controls
- Eliminates loading all active sources into memory

### Sources Index Pagination UX
- Current: prev/next buttons only — no page count, no jump-to-page
- Needed: add total page count display and ability to jump to a specific page
- Per-page control and filter preservation already work fine

### Source Count Display
- Keep existing dashboard stats cards (total sources, active, failed, total items, fetches today)
- Add health status distribution as inline badge counts: Healthy N, Warning N, Declining N, Critical N
- Aggregates stay visible above the fold regardless of which schedule page is active

### Open (Claude's discretion)
- Pagination component reuse: sources index and dashboard schedule sections can share the same pagination partial/helper
- Page size per section: default 10-15 per schedule bucket (smaller than sources index 25) to keep dashboard compact
- Empty bucket handling: hide schedule sections with 0 sources rather than showing empty groups

## Deferred Ideas
None.
