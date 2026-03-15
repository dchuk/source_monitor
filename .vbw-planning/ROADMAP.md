# Roadmap

**Milestone:** rails-audit-and-modal

## Phases

- [x] Phase 01: Quick Wins & Security
- [x] Phase 02: Model Layer Hardening
- [x] Phase 03: Controller & Route Refactoring
- [x] Phase 04: Job & Pipeline Reliability
- [x] Phase 05: View Layer Extraction
- [x] Phase 06: Test Infrastructure
- [ ] Phase 07: Rails Audit Round 2

## Phase Details

### Phase 01: Quick Wins & Security

**Goal:** Fix high-priority security issues and low-effort quick wins from the Rails audit (findings M1, M3, M5, M12, C6, C9, V2, V8, V10, V11).

**Success Criteria:**
- ImportHistoryDismissalsController scoped to current user
- DashboardController uses explicit parameter allowlist (no .permit!)
- ScrapeLog has by_source, by_status, by_item scopes
- Scrape status badge logic extracted to helper
- MutationObserver disconnect leak fixed

**Plans:**
- [x] Plan 01: Security & Controller Fixes
- [x] Plan 02: Model & Job Fixes
- [x] Plan 03: View & Helper Extraction

### Phase 02: Model Layer Hardening

**Goal:** Fix model-level issues: N+1 callbacks, missing scopes, raw SQL extraction, date range scopes (findings M4, M6, M7, M8, M9).

**Success Criteria:**
- Loggable concern has date range scopes (since, before, today, by_date_range)
- Composite indexes on log tables for source/item + started_at queries
- ItemContent N+1 in before_save fixed
- Item has after_create_commit callback for content records
- Source.scrape_candidates extracted to ScrapeCandidatesQuery

**Plans:**
- [x] Plan 01: Loggable Date Scopes & Composite Indexes
- [x] Plan 02: ItemContent N+1 Fix & Item Callback Guard
- [x] Plan 03: Scrape Candidates Query Object Extraction

### Phase 03: Controller & Route Refactoring

**Goal:** Improve CRUD compliance and controller patterns (findings C1-C5, C7, C8, C10).

**Success Criteria:**
- Custom scrape actions extracted to dedicated ItemScrapesController
- Favicon cooldown logic moved from controller to Source model
- SourcesController index metrics extracted to analytics object
- Import step dispatch uses handler registry pattern
- Controller concerns follow single-responsibility principle

**Requirements:** C1 (ItemScrapesController), C2 (favicon cooldown), C4 (sources metrics), C5 (step dispatch), C7 (pluralizer decoupling), C8 (logging), C10 (redirect validation)

**Plans:**
- [x] Plan 01: Extract ItemScrapesController & Simplify Logging (C1, C8)
- [x] Plan 02: Move Favicon Cooldown to Source Model (C2)
- [x] Plan 03: Extract Sources Index Metrics & Redirect Validation (C4, C10)
- [x] Plan 04: Decouple Pluralizer from SourceTurboResponses (C7)
- [x] Plan 05: Import Step Handler Registry (C3, C5)

### Phase 04: Job & Pipeline Reliability

**Goal:** Improve error handling, retry logic, and service patterns in jobs and pipeline (findings S1-S6).

**Success Criteria:**
- ImportSessionHealthCheckJob handles ActiveRecord::Deadlocked
- FetchFeedJob retry/circuit-breaker logic extracted to service
- Transient vs fatal error classification in FaviconFetchJob and DownloadContentImagesJob
- Result pattern added to EventPublisher, RetentionHandler, FollowUpHandler, Scheduler
- Pipeline error paths have consistent logging

**Requirements:** S1 (deadlock), S2 (retry extraction), S3 (job logic), S4 (Result pattern), S5 (error logging), S6 (error classification)

### Phase 05: View Layer Extraction

**Goal:** Extract view logic into ViewComponents, presenters, and helpers (findings V1-V15).

**Success Criteria:**
- Sources index filter logic extracted to ViewComponent or Presenter
- FilterButtonGroup ViewComponent for shared filter patterns
- SourceDetailsPresenter replaces inline hash formatting
- Dropdown controller async loading stabilized
- Icon system replaces inline SVG repetition

**Requirements:** V1 (filter extraction), V3 (N+1 documentation), V4 (targeted Turbo Streams), V5 (FilterButtonGroup), V6 (dropdown async), V7 (dropdown isolation), V9 (icon system), V12 (frame naming), V13 (namespace pollution), V14 (SourceDetailsPresenter), V15 (ModalComponent)

### Phase 06: Test Infrastructure

**Goal:** Consolidate test patterns, shared factories, and improve coverage discipline (findings T1-T17).

**Success Criteria:**
- Shared test factory module (test/support/model_factories.rb) replaces per-file duplication
- VCR cassette maintenance documented
- ApplicationSystemTestCase has proper wait configuration and cleanup
- Consistent mocking approach documented and applied
- Isolated unit tests for extracted sub-modules (FetchRunner, SourceUpdater, etc.)

**Requirements:** T1 (VCR docs), T2 (fixture coupling), T3 (sub-module tests), T4 (integration gaps), T5 (system test coverage), T6 (shared factories), T7 (mocking), T8 (WebMock stubs), T9 (system test base), T10 (error paths), T11 (time tests), T12 (job naming), T13 (counter cache), T14 (test naming), T15 (shared behavior), T16 (wait config), T17 (temp cleanup)

### Phase 07: Rails Audit Round 2

**Goal:** Address 44 remaining findings from the 2026-03-14 Rails best practices audit. Focuses on job shallowness (extracting business logic from 4 jobs), data integrity (LogCleanupJob orphaned records), model correctness (health_status validation/default mismatch), controller DRY patterns (shared concerns), view layer improvements (StatusBadgeComponent, presenters, accessibility), and test parallel-safety.

**Success Criteria:**
- LogCleanupJob cascades deletes to LogEntry records (H1)
- ImportOpmlJob, ScrapeItemJob, DownloadContentImagesJob business logic extracted to services (H2-H4)
- Duplicated scrape rate-limiting consolidated to single location (H5)
- Pagination tests are parallel-safe (H6)
- Source health_status default aligned with DB + inclusion validation added (M1-M2)
- `set_source` extracted to shared concern across 7 controllers (M6)
- `rescue_from RecordNotFound` added to ApplicationController (M5)
- StatusBadgeComponent replaces 12+ duplicated badge patterns (M20)
- Modals have `role="dialog"`, `aria-modal`, and focus trapping (M22-M23)

**Requirements:** H1-H6, M1-M14, M17-M26, L1-L5, L7-L12, L14-L23, L27-L28, L30

## Progress

| Phase | Status | Plans | Done |
|-------|--------|-------|------|
| 01 | ✓ Complete | 3 | 3 |
| 02 | ✓ Complete | 3 | 3 |
| 03 | ✓ Complete | 5 | 5 |
| 04 | ✓ Complete | 3 | 3 |
| 05 | ✓ Complete | 4 | 4 |
| 06 | ✓ Complete | 4 | 4 |
| 07 | ● Done |
