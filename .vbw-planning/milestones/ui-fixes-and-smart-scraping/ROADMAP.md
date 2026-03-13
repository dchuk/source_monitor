# Roadmap

**Milestone:** ui-fixes-and-smart-scraping

## Phases

- [x] Phase 01: UI Polish & Bug Fixes
- [x] Phase 02: Feed Reliability
- [x] Phase 03: Dashboard Pagination
- [x] Phase 04: Smart Scrape Recommendations
- [ ] Phase 05: Simplify Source Status
- [ ] Phase 06: Ultimate Turbo Modal Integration

## Phase Details

### Phase 01: UI Polish & Bug Fixes

**Goal:** Fix UI/UX issues: dismissible OPML import banner, SVG favicon rendering, URL in activity heading, and sortable columns on sources index (New Items/Day, Avg Feed Words, Avg Scraped Words).

**Success Criteria:**
- OPML import banner has a dismiss/close button that hides it
- SVG favicons (e.g., ozorn.in) render correctly or fall back gracefully
- Recent activity entries show the source URL in the bold heading row
- New Items/Day, Avg Feed Words, and Avg Scraped Words columns are sortable on the sources index

**Requirements:** UI polish, bug fixes

### Phase 02: Feed Reliability

**Goal:** Fix fetch pipeline reliability issues: "No valid XML parser" errors for Cloudflare-challenged feeds, and ConcurrencyError (advisory lock busy) when force-fetching a source that's already locked.

**Success Criteria:**
- Cloudflare-blocked feeds produce clear, actionable error messages
- Where possible, bypass or handle Cloudflare challenges
- Fetch logs show meaningful diagnostics for parser failures
- FetchRunner handles advisory lock contention gracefully for force fetches (no permanent failure after 4 retries)
- ConcurrencyError with `force: true` either waits/retries or skips cleanly instead of failing the job

**Requirements:** Feed reliability, error handling

### Phase 03: Dashboard Pagination

**Goal:** Add pagination or grouping to the dashboard sources list to handle large numbers of sources without overwhelming the page.

**Success Criteria:**
- Dashboard renders efficiently with 100+ sources
- Sources are paginated or grouped in a usable way
- Navigation between pages/groups is intuitive

**Requirements:** Dashboard UX, performance

### Phase 04: Smart Scrape Recommendations

**Goal:** Build a system that identifies sources with consistently low average word counts in feed entries, recommends switching them to scraping, and supports bulk scrape enablement with optional test-first confirmation.

**Success Criteria:**
- Sources with low average word count are surfaceable via filter or dedicated view
- Bulk action to enable scraping for selected sources
- Optional scrape test to compare feed vs scraped word count before committing
- Clear UI showing the word count differential

**Requirements:** Analytics, scraping, bulk operations

### Phase 05: Simplify Source Status

**Goal:** Simplify the confusing source status/health system by separating operational state (active/paused) from health diagnosis (working/declining/improving/failing). Currently auto-paused sources still appear as "active" in filters, and 7 overlapping health statuses create too many permutations. Consolidate to a clean two-axis model.

**Success Criteria:**
- Health statuses reduced from 7 to 4: working, declining, improving, failing
- Auto-pause no longer masks health diagnosis — a source can be "failing AND auto-paused"
- Active filter correctly excludes auto-paused sources
- Health filter shows only: Working, Declining, Improving, Failing
- Health badge and interactive actions updated for new status values
- SourceHealthMonitor decision tree simplified
- All existing tests updated to reflect new status values

**Requirements:** UX simplification, health monitoring, status model

### Phase 06: Ultimate Turbo Modal Integration

**Goal:** Replace hand-rolled `<dialog>` modals with [ultimate_turbo_modal](https://github.com/cmer/ultimate_turbo_modal) for a polished, accessible, and consistent modal experience across the engine. Covers scrape test results modal, bulk scrape confirmation, and any future modal use cases.

**Success Criteria:**
- `ultimate_turbo_modal` gem integrated and configured
- Scrape test results modal uses UTM instead of raw `<dialog>`
- Bulk scrape confirmation modal migrated to UTM
- Consistent animation, stacking, and accessibility (focus trap, escape key) across all modals
- Existing modal Stimulus controller simplified or removed

**Requirements:** UX polish, accessibility, dependency management

## Progress

| Phase | Status | Plans | Done |
|-------|--------|-------|------|
| 01 | ● Done |
| 02 | ● Done | 4 | 4 |
| 03 | ● Done | 4 | 4 |
| 04 | ● Done | 5 | 5 |
| 05 | ● Done |
| 06 | ○ Pending | 0 | 0 |
