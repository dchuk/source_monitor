<!-- VBW ROADMAP -- Phase decomposition with requirement mapping -->
<!-- Created during /vbw scope -->

# SourceMonitor Generator Enhancements Roadmap

**Milestone:** generator-enhancements
**Goal:** Make the install generator and verification suite catch the two most common host-app setup failures: missing Procfile.dev jobs entry and missing recurring_schedule dispatcher wiring.

## Phases

1. [x] ~~Phase 0: Documentation Gaps~~ (shipped via quick fix ea788ea)
2. [x] Phase 1: Install Generator Steps (Procfile.dev + Queue Config)
3. [x] Phase 2: Recurring Schedule Verifier
4. [x] Phase 3: Skills & Documentation Alignment
5. [x] Phase 4: Dashboard UX Improvements
6. [x] Phase 5: Active Storage Image Downloads
7. [x] Phase 6: Netflix Feed Investigation

## Phase Details

### Phase 1: Install Generator Steps

**Goal:** Add two new idempotent steps to the install generator: (a) patch `Procfile.dev` with a `jobs:` entry for Solid Queue, and (b) patch the queue config dispatcher with `recurring_schedule: config/recurring.yml`.

**Requirements:** REQ-16, REQ-17, REQ-18

**Success Criteria:**
- `bin/rails generate source_monitor:install` patches Procfile.dev when present (idempotent, skip if entry exists)
- `bin/rails generate source_monitor:install` patches queue.yml dispatcher with recurring_schedule (idempotent)
- Both steps wired into `Setup::Workflow` for the guided installer
- Generator tests cover: fresh file, existing file with entry, existing file without entry, missing file
- `bin/rails test` passes, RuboCop clean

### Phase 2: Recurring Schedule Verifier

**Goal:** Add a `RecurringScheduleVerifier` to the verification suite that checks whether recurring tasks are actually registered with Solid Queue dispatchers, and enhance the existing `SolidQueueVerifier` to suggest Procfile.dev when workers aren't detected.

**Requirements:** REQ-19, REQ-20

**Success Criteria:**
- `bin/source_monitor verify` checks that recurring tasks are registered (not just that workers heartbeat)
- Warning when no recurring tasks found with actionable remediation message
- SolidQueueVerifier remediation mentions Procfile.dev for `bin/dev` users
- Verifier tests with mocked Solid Queue state
- `bin/rails test` passes, RuboCop clean

### Phase 3: Skills & Documentation Alignment

**Goal:** Update all `sm-*` skills and docs to reflect that the generator now automatically handles Procfile.dev and recurring_schedule wiring. Remove manual steps that are now automated.

**Requirements:** REQ-21

**Success Criteria:**
- sm-host-setup skill reflects new generator capabilities (auto-patching, not manual steps)
- sm-configure skill references the automatic recurring_schedule wiring
- docs/setup.md updated to note the generator handles both automatically
- docs/troubleshooting.md updated with improved diagnostics
- setup-checklist.md reflects automation (checked by default, not manual)

### Phase 4: Dashboard UX Improvements

**Goal:** Show source URLs in fetch log entries for both successes and failures on the dashboard, and make links to sources and items clickable (opening in a new tab).

**Requirements:** REQ-22, REQ-23

**Success Criteria:**
- Fetch log entries on the dashboard display the source URL alongside the existing summary
- Both success and failure fetch logs show the URL
- Source names and item titles are clickable links that open in a new tab
- Existing dashboard layout is preserved
- `bin/rails test` passes, RuboCop clean

### Phase 5: Active Storage Image Downloads

**Goal:** Add a configurable option to download inline images from feed items to Active Storage instead of loading them directly from the source URL. This prevents broken images when sources go offline and improves page load performance.

**Requirements:** REQ-24

**Success Criteria:**
- New configuration option (`config.images.download_to_active_storage` or similar) defaults to `false`
- When enabled, inline images in item content are detected and downloaded to Active Storage
- Original image URLs are replaced with Active Storage URLs in the stored content
- Images that fail to download gracefully fall back to original URLs
- Configuration is documented in sm-configure skill
- `bin/rails test` passes, RuboCop clean

### Phase 6: Netflix Feed Investigation

**Goal:** Investigate and fix the failing fetch for `https://netflixtechblog.com/feed`. Determine whether the issue is in the feed parser, HTTP client configuration, or content format, and apply appropriate fixes.

**Requirements:** REQ-25

**Success Criteria:**
- Root cause identified and documented
- Fix applied (parser, HTTP client, or configuration change)
- Netflix Tech Blog feed fetches successfully
- No regressions in other feed types
- `bin/rails test` passes, RuboCop clean

## Progress

| Phase | Status | Plans |
|-------|--------|-------|
| 0 | Complete | - |
| 1 | Complete | PLAN-01 (5 tasks, 4 commits) |
| 2 | Complete | PLAN-01 (5 tasks, 1 commit) |
| 3 | Complete | PLAN-01 (5 tasks, 1 commit) |
| 4 | Complete | PLAN-01 (5 tasks, 5 commits) |
| 5 | Complete | PLAN-01 (4 tasks, 5 commits) + PLAN-02 (4 tasks, 4 commits) |
| 6 | Complete | PLAN-01 (5 tasks, 5 commits) |

## Requirement Mapping

| REQ | Phase | Description |
|-----|-------|-------------|
| REQ-16 | 1 | Generator patches Procfile.dev with jobs: entry |
| REQ-17 | 1 | Generator patches queue config with recurring_schedule |
| REQ-18 | 1 | Guided workflow integrates both new steps |
| REQ-19 | 2 | RecurringScheduleVerifier checks recurring task registration |
| REQ-20 | 2 | SolidQueueVerifier remediation mentions Procfile.dev |
| REQ-21 | 3 | Skills and docs reflect automated setup |
| REQ-22 | 4 | Fetch logs show source URL on dashboard |
| REQ-23 | 4 | Dashboard links clickable in new tab |
| REQ-24 | 5 | Download inline images to Active Storage |
| REQ-25 | 6 | Fix Netflix Tech Blog feed fetch |
