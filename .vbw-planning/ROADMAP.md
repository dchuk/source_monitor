# Roadmap

## Milestone: polish-and-reliability

### Phases

1. [x] **Backend Fixes** -- Fix browser User-Agent default, health check status transitions, and smarter scrape rate limiting
2. [x] **Favicon Support** -- Automatically save source favicons via Active Storage with background fetch job
3. [x] **Toast Stacking** -- Cap visible toast notifications with click-to-expand for bulk operation UX

### Phase Details

#### Phase 1: Backend Fixes

**Goal:** Fix three independent backend issues: bot-blocked feeds due to User-Agent, health check not updating status, and overly aggressive scrape limiting.

**Requirements:**
- REQ-UA-01: Change default User-Agent from "SourceMonitor/VERSION" to a browser-like string
- REQ-HC-01: After a successful manual health check on a declining/critical/warning source, trigger SourceHealthMonitor re-evaluation or directly transition status to "improving"
- REQ-SL-01: Refine max_in_flight_per_source to only count actively-running scrape jobs (not queued ones)

**Success Criteria:**
- [ ] Default UA string resembles a real browser (e.g., Mozilla/5.0 compatible)
- [ ] Successful manual health check on a declining source transitions it to improving
- [ ] Scrape limit counts only actively-running jobs, queued items don't count toward the cap
- [ ] All existing tests pass, new tests cover changed behavior
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 2: Favicon Support

**Goal:** Automatically fetch and store source favicons using Active Storage, displayed in the UI next to source names.

**Requirements:**
- REQ-FAV-01: Add has_one_attached :favicon to Source model with if defined?(ActiveStorage) guard
- REQ-FAV-02: Create FaviconFetchJob to discover favicon URL from website_url (link[rel=icon], /favicon.ico fallback)
- REQ-FAV-03: Trigger favicon fetch on source creation and periodically on successful fetches (if missing)
- REQ-FAV-04: Display favicon in source list/show views with fallback placeholder

**Success Criteria:**
- [ ] Source model has has_one_attached :favicon with Active Storage guard
- [ ] FaviconFetchJob discovers and downloads favicons from website_url
- [ ] Favicon fetched on source creation and refreshed if missing
- [ ] Favicon displayed in source views with graceful fallback
- [ ] Host apps without Active Storage don't crash
- [ ] All existing tests pass, new tests cover favicon paths
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 3: Toast Stacking

**Goal:** Replace uncapped toast notification stacking with a max-visible cap and "+N more" hover-to-expand pattern for cleaner UX during bulk operations.

**Requirements:**
- REQ-TOAST-01: Cap visible toasts at a configurable max (default: 3)
- REQ-TOAST-02: When cap exceeded, show a "+N more" badge/indicator
- REQ-TOAST-03: Hovering the notification area expands to show all stacked toasts
- REQ-TOAST-04: Individual toasts still auto-dismiss after their delay

**Success Criteria:**
- [ ] No more than 3 toasts visible simultaneously (configurable)
- [ ] Overflow indicator shows count of hidden toasts
- [ ] Hover/focus expands the stack to show all
- [ ] Auto-dismiss still works, stack count updates as toasts expire
- [ ] No regressions in existing toast behavior (inline + broadcast paths)
- [ ] RuboCop zero offenses

### Progress

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. Backend Fixes | Complete | 3 | 3 |
| 2. Favicon Support | Complete | 3 | 3 |
| 3. Toast Stacking | Complete | 1 | 1 |
