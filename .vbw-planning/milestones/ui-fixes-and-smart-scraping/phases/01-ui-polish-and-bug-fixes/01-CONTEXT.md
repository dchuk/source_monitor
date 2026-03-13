# Phase 01: UI Polish & Bug Fixes -- Context

Gathered: 2026-03-05
Calibration: architect

## Phase Boundary

Fix UI/UX issues: dismissible OPML import banner, SVG favicon rendering, URL in activity heading, and sortable columns on sources index (New Items/Day, Avg Feed Words, Avg Scraped Words).

## Decisions

### OPML Banner Dismissal
- Per-import persistence: add `dismissed_at` timestamp to ImportHistory record
- New imports show a fresh banner; dismissed ones stay gone
- Dismiss action via Turbo Stream (inline removal, no page reload)
- Endpoint: PATCH or DELETE to mark import as dismissed

### SVG Favicon Handling
- Convert SVG favicons to PNG on ingest using ImageMagick (MiniMagick)
- Eliminates security risk from inline SVG scripts/external references
- Consistent rendering across all contexts (dashboard, source detail, etc.)
- Existing SVG favicons: re-fetched gradually on next scheduled fetch cycle (no migration job)

### Recent Activity Heading Layout
- URL leads the heading row: "fhur.me -- Fetch #2210 FETCH"
- Source name line below is removed (URL serves as the source identifier)
- Keeps the existing badge/stats layout intact

### Open (Claude's discretion)
- Sortable columns: match existing Items/Last Fetch sort pattern (server-side via Ransack, sort icons in column headers)
- Sort direction toggle: match existing asc/desc cycle behavior

## Deferred Ideas
None.
