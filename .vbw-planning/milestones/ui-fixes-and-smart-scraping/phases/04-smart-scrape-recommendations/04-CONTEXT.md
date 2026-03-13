# Phase 04: Smart Scrape Recommendations — Context

Gathered: 2026-03-08
Calibration: architect

## Phase Boundary
Build a system that identifies sources with consistently low average word counts in feed entries, recommends switching them to scraping, and supports bulk scrape enablement with optional test-first confirmation.

## Decisions

### Low Word Count Threshold
- Fixed threshold approach: sources with avg feed word count below a configurable threshold are flagged as scrape candidates
- Global config only: single threshold via `SourceMonitor.configure { |c| c.scrape_recommendation_threshold = N }`
- No per-source override

### Recommendation Surfacing
- Dashboard widget: summary count of recommended sources with link to filtered sources index
- Sources index badge: visual indicator on source rows that meet the threshold criteria
- No dedicated/standalone recommendations page

### Test-First Scrape Flow
- Single item preview: pick one recent item, scrape it on-demand, show feed word count vs scraped word count
- Renders on a separate comparison page (not modal or inline)
- User confirms or cancels after reviewing the comparison

### Bulk Enablement UX
- Checkboxes on source rows for selective enable + "Enable All Matching" button for bulk
- Confirmation modal before enabling: shows count of sources being enabled + warning about scrape job volume
- Standard action bar pattern when checkboxes are selected

### Open (Claude's discretion)
- Scraper adapter selection for newly-enabled sources (use default configured adapter)
- Threshold default value (suggest 200 words as starting point, adjustable via config)
- Dashboard widget position (alongside existing stats or in a separate recommendations section)

## Deferred Ideas
None.
