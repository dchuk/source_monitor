# SourceMonitor Engine - Rails 8 Thin Slice TDD Development Roadmap

## Active Slice Tracker

- PRD: `tasks/prd-setup-workflow-streamlining.md`
- Task list: `tasks/tasks-setup-workflow-streamlining.md`

## Coverage Workflow

- Always run `bin/test-coverage` followed by `bin/check-diff-coverage` before pushing.
- When legitimate changes lower coverage, run `bin/update-coverage-baseline` and commit the refreshed `config/coverage_baseline.json` in the same branch.
- CI enforces these steps (diff coverage + setup test presence), so follow them locally to avoid failures.

## Phase 01: Minimal Engine Setup & Rails Integration

**Goal: Get engine mountable in host Rails 8 app immediately**

### 01.01 Generate Mountable Engine

- [x] 01.01.01 Generate Rails engine with `rails plugin new source_monitor --mountable`
- [x] 01.01.02 Configure isolate_namespace in engine.rb

### 01.02 Create Installation Generator

- [x] 01.02.01 Write test for install generator existence
- [x] 01.02.02 Create basic install generator class
- [x] 01.02.03 Make mount path configurable (default /source_monitor)
- [x] 01.02.04 Add generator usage instructions to README

### 01.03 Mount Engine in Host App

- [x] 01.03.01 Write test for route mounting
- [x] 01.03.02 Generator adds configurable mount to host routes.rb
- [x] 01.03.03 Create minimal ApplicationController
- [x] 01.03.04 Test engine responds at mounted path

**Deliverable: Engine installs and mounts at configurable path in Rails 8 app**
**Test: Visit mounted path and see welcome page**

---

## Phase 02: Testing Infrastructure & Observability

**Goal: Solid testing and monitoring foundation**

### 02.01 Setup Test Framework

- [x] 02.01.01 Configure MiniTest with Rails system tests
- [x] 02.01.02 Add WebMock and VCR for HTTP stubbing
- [x] 02.01.03 Create RSS, Atom, JSON Feed fixtures
- [x] 02.01.04 Add edge case fixtures (no GUID, malformed dates)

### 02.02 Add Observability

- [x] 02.02.01 Setup ActiveSupport::Notifications events
- [x] 02.02.02 Add source_monitor.fetch.start/finish events
- [x] 02.02.03 Create /health endpoint
- [x] 02.02.04 Add basic metrics collection module

**Deliverable: Comprehensive testing and observability from day one**
**Test: Run test suite and visit /health endpoint**

---

## Phase 03: Complete Data Model Foundation

**Goal: Complete data model with all necessary fields and proper constraints**

### 03.01 Create Source Model & Migration

- [x] 03.01.01 Create sources migration with all fields: name, feed_url (unique/indexed), website_url, active (default true/indexed), feed_format, fetch_interval_hours (default 6), next_fetch_at (indexed), last_fetched_at, last_fetch_duration_ms, last_http_status, last_error (text), last_error_at, etag, last_modified, failure_count (default 0), backoff_until, items_count (counter cache), scraping_enabled (default false), auto_scrape (default false), scrape_settings (jsonb), scraper_adapter (default 'readability'), requires_javascript (default false), custom_headers (jsonb), items_retention_days, max_items, metadata (jsonb), timestamps
- [x] 03.01.02 Create SourceMonitor::Source model with validations
- [x] 03.01.03 Add URL validation and normalization
- [x] 03.01.04 Add scopes for active, due_for_fetch, failed, healthy
- [x] 03.01.05 Test creating source via console and UI form

### 03.02 Create Item Model & Migration

- [x] 03.02.01 Create items migration with all fields: source_id (references/indexed/fk), guid (indexed), content_fingerprint (indexed SHA256), title, url (indexed), canonical_url, author, authors (jsonb), summary (text), content (text), scraped_html (text), scraped_content (text), scraped_at, scrape_status (indexed), published_at (indexed), updated_at_source, categories (jsonb), tags (jsonb), keywords (jsonb), enclosures (jsonb), media_thumbnail_url, media_content (jsonb), language, copyright, comments_url, comments_count, metadata (jsonb), timestamps; add unique constraints on (source_id, guid) and (source_id, content_fingerprint)
- [x] 03.02.02 Create SourceMonitor::Item model
- [x] 03.02.03 Add associations to Source
- [x] 03.02.04 Add validations and scopes
- [x] 03.02.05 Test creating items programmatically

### 03.03 Create FetchLog Model & Migration

- [x] 03.03.01 Create fetch_logs migration with all fields: source_id (references/indexed/fk), success (indexed), items_created (default 0), items_updated (default 0), items_failed (default 0), started_at (indexed), completed_at, duration_ms, http_status, http_response_headers (jsonb), error_class, error_message (text), error_backtrace (text), feed_size_bytes, items_in_feed, job_id (indexed), metadata (jsonb), created_at (indexed)
- [x] 03.03.02 Create SourceMonitor::FetchLog model
- [x] 03.03.03 Add associations and scopes
- [x] 03.03.04 Test log creation with various scenarios

### 03.04 Create ScrapeLog Model & Migration

- [x] 03.04.01 Create scrape_logs migration with all fields: item_id (references/indexed/fk), source_id (references/indexed/fk), success (indexed), started_at, completed_at, duration_ms, http_status, scraper_adapter, content_length, error_class, error_message (text), metadata (jsonb), created_at (indexed)
- [x] 03.04.02 Create SourceMonitor::ScrapeLog model
- [x] 03.04.03 Add associations
- [x] 03.04.04 Test scrape log tracking

**Deliverable: Complete, production-ready data model with all necessary fields**
**Test: Create all models via console, verify constraints and associations work**

---

## Phase 04: Simple Admin Interface with Tailwind

**Goal: Functional admin UI using Rails defaults + Tailwind**

### 04.01 Setup Tailwind CSS

- [x] 04.01.01 Add tailwindcss-rails to gemspec
- [x] 04.01.02 Generate Tailwind configuration for engine
- [x] 04.01.03 Scope CSS to .fm-admin namespace
- [x] 04.01.04 Create base layout with navigation

### 04.02 Create Dashboard

- [x] 04.02.01 Create DashboardController with index action
- [x] 04.02.02 Build stats partial showing source counts
- [x] 04.02.03 Add recent activity feed (latest logs)
- [x] 04.02.04 Display quick action buttons
- [x] 04.02.05 Test dashboard loads and shows data

### 04.03 Build Source Management

- [x] 04.03.01 Create SourcesController with full CRUD
- [x] 04.03.02 Build index view with status indicators
- [x] 04.03.03 Create form partial for new/edit
- [x] 04.03.04 Add show view with source details
- [x] 04.03.05 Test complete source lifecycle

### 04.04 Add Item Browser

- [x] 04.04.01 Create ItemsController with index and show
- [x] 04.04.02 Build paginated item list view
- [x] 04.04.03 Create item detail view with all content versions
- [x] 04.04.04 Add simple search by title
- [x] 04.04.05 Test browsing and viewing items

### 04.05 Create Log Viewers

- [x] 04.05.01 Create FetchLogsController with index and show
- [x] 04.05.02 Build log list view with filtering
- [x] 04.05.03 Create log detail view showing all data
- [x] 04.05.04 Add scrape logs view
- [x] 04.05.05 Test viewing success and failure logs

**Deliverable: Complete functional admin UI using Rails + Tailwind only**
**Test: Navigate through all admin pages, perform CRUD operations**

---

## Phase 05: Modern HTTP Stack & Feed Fetching

**Goal: Reliable feed fetching with logging using Feedjira**

### 05.01 Setup Faraday HTTP Client & Feedjira

- [x] 05.01.01 Add feedjira, faraday, and faraday-retry to gemspec
- [x] 05.01.02 Configure Feedjira global options (parser order, whitespace)
- [x] 05.01.03 Configure timeouts, redirects, compression
- [x] 05.01.04 Add retry middleware with exponential backoff and proxy support
- [x] 05.01.05 Smoke-test HTTP + Feedjira configuration against sample feeds

### 05.02 Build Feed Fetcher with Feedjira & Conditional GET

- [x] 05.02.01 Write FeedFetcher service tests with VCR using Feedjira.parse
- [x] 05.02.02 Implement ETag and Last-Modified support
- [x] 05.02.03 Handle 304 Not Modified responses
- [x] 05.02.04 Leverage Feedjira auto-detection for RSS/Atom/JSON parsing
- [x] 05.02.05 Validate Feedjira parser coverage across varied feed types

### 05.03 Add Structured Error Handling

- [x] 05.03.01 Create FetchError class hierarchy
- [x] 05.03.02 Log all fetch attempts to FetchLog
- [x] 05.03.03 Update source status on fetch
- [x] 05.03.04 Emit ActiveSupport notifications
- [x] 05.03.05 Test error scenarios (timeout, 404, malformed)

### 05.04 Implement Rate Limiting

- [x] 05.04.01 Add adaptive fetch interval logic based on feed activity
- [x] 05.04.02 Add source-level jitter to avoid stampedes
- [x] 05.04.03 Respect backoff_until field
- [x] 05.04.04 Update failure_count on errors
- [x] 05.04.05 Test rate limiting behavior

**Deliverable: Production-grade fetching with Feedjira-backed parsing**
**Test: Fetch real feeds via console, verify Feedjira parsing and conditional GET**

---

## Phase 06: Item Processing with Complete Metadata

**Goal: Extract and store all feed item data via Feedjira entries**

### 06.01 Build Item Creator Service

- [x] 06.01.01 Write tests for item creation using Feedjira entry objects
- [x] 06.01.02 Generate content fingerprints from title+url+content
- [x] 06.01.03 Normalize and canonicalize URLs
- [x] 06.01.04 Handle missing GUIDs gracefully
- [x] 06.01.05 Test item creation with Feedjira across various feed formats

### 06.02 Extract All Metadata Fields

- [x] 06.02.01 Map Feedjira fields: title, url, guid, author, content
- [x] 06.02.02 Extract authors array and handle DC creator via Feedjira APIs
- [x] 06.02.03 Extend Feedjira parsers to expose categories, tags, keywords
- [x] 06.02.04 Extract enclosures for media (podcasts/videos)
- [x] 06.02.05 Parse media:thumbnail and media:content
- [x] 06.02.06 Expose comments URL and count via Feedjira parser extensions
- [x] 06.02.07 Capture all other fields in metadata JSONB
- [x] 06.02.08 Test metadata extraction with real feeds through Feedjira

### 06.03 Implement Deduplication Logic

- [x] 06.03.01 Check GUID uniqueness first
- [x] 06.03.02 Fall back to content fingerprint
- [x] 06.03.03 Use upsert for idempotent creation
- [x] 06.03.04 Track duplicate attempts in logs
- [x] 06.03.05 Test deduplication with repeated fetches

### 06.04 Wire Up Feed Fetcher to Item Creator

- [x] 06.04.01 Integrate FeedFetcher with ItemCreator
- [x] 06.04.02 Update items_count counter cache
- [x] 06.04.03 Log items created/updated/failed
- [x] 06.04.04 Test end-to-end fetch and item creation
- [x] 06.04.05 Add manual fetch button in admin UI

**Deliverable: Complete item metadata extraction and storage via Feedjira**
**Test: Fetch feed via admin UI, verify Feedjira-driven items have complete metadata**

---

## Phase 07: Content Scraping with Multiple Storage Layers

**Goal: Store raw HTML and extracted content in a dedicated table while complementing Feedjira data**

### 07.01 Create Scraper Adapter Interface

- [x] 07.01.01 Define Scrapers::Base abstract class
- [x] 07.01.02 Create contract tests for adapter interface
- [x] 07.01.03 Add settings parameter support
- [x] 07.01.04 Document adapter requirements

### 07.02 Implement Readability Scraper

- [x] 07.02.01 Add nokolexbor for fast HTML parsing
- [x] 07.02.02 Add ruby-readability for extraction
- [x] 07.02.03 Create Scrapers::Readability adapter
- [x] 07.02.04 Support custom CSS selectors via scrape_settings
- [x] 07.02.05 Test scraper with various article pages

### 07.03 Persist Scraped Content Separately

- [x] 07.03.01 Create dedicated table (e.g. item_contents) with scraped_html and scraped_content columns
- [x] 07.03.02 Add has_one association from Item and migrate existing data
- [x] 07.03.03 Update scraping pipeline to write to the associated content record
- [x] 07.03.04 Ensure Items table drops scraped_html and scraped_content columns while keeping status fields
- [x] 07.03.05 Test persistence using the separate table alongside Feedjira content

### 07.04 Add Scraping UI Controls

- [x] 07.04.01 Add scraping configuration form to source edit
- [x] 07.04.02 Add manual scrape button on item detail page
- [x] 07.04.03 Display all content versions in item view with Feedjira comparison
- [x] 07.04.04 Show scraping status and errors
- [x] 07.04.05 Test manual scraping workflow

**Deliverable: Multi-layer content storage aligned with Feedjira base content and smaller Items table**
**Test: Scrape article via admin UI, verify scraped layers stored via associated content record**

---

## Phase 08: Background Jobs with Solid Queue

**Goal: Unified job orchestration that powers both async processing and manual actions without duplicating logic**

### 08.01 Establish Job Infrastructure

- [x] 08.01.01 Ensure Solid Queue/Postgres are the default while allowing host apps to override ActiveJob backend if already configured
- [x] 08.01.02 Introduce `SourceMonitor::ApplicationJob` that inherits the host `ApplicationJob` when present, falling back to `ActiveJob::Base`
- [x] 08.01.03 Provide configurable queue names/concurrency that respect host settings and avoid namespace clashes
- [x] 08.01.04 Add lightweight job visibility in the engine (e.g., queue depth/last run) and document optional Mission Control integration without hard dependency
- [x] 08.01.05 Verify job execution path inside dummy app with Postgres-backed Solid Queue

### 08.02 Implement FetchFeedJob Pipeline

- [x] 08.02.01 Create `FetchFeedJob` as the canonical entry point for fetching, delegating to existing fetch orchestration logic
- [x] 08.02.02 Extract a shared fetch runner/enqueuer used by both the job and manual “Fetch Now” UI to prevent duplicated code paths
- [x] 08.02.03 Guard concurrent fetches via advisory locking or equivalent coordination
- [x] 08.02.04 After processing, enqueue `ScrapeItemJob` instances for any new items flagged for scraping via the shared enqueuer
- [x] 08.02.05 Add tests covering job execution, retry behavior, and automatic follow-up scraping

### 08.03 Implement ScrapeItemJob Pipeline

- [x] 08.03.01 Create `ScrapeItemJob` as the canonical scraping entry point that reuses the existing scraper orchestration
- [x] 08.03.02 Introduce shared scraping enqueue logic invoked by both background jobs and manual UI actions
- [x] 08.03.03 Respect per-source scraping configuration and deduplicate in-flight jobs when queuing
- [x] 08.03.04 Persist `ScrapeLog` updates and propagate status/errors consistently with the manual flow
- [x] 08.03.05 Add tests for scraping job workflow, including cases triggered by both automatic and manual paths

### 08.04 Unify UI and Job Queueing

- [x] 08.04.01 Update manual fetch button to call the shared fetch enqueuer so the UI and jobs share the same foundation
- [x] 08.04.02 Update manual scrape actions to leverage the shared scraping enqueuer
- [x] 08.04.03 Surface job state/metrics in the admin dashboard using the lightweight visibility layer from 08.01
- [x] 08.04.04 Expose optional Mission Control links/documentation when the host app enables it
- [x] 08.04.05 Add system/integration tests ensuring manual actions enqueue the proper jobs and display status

### 08.05 Separate readability from scraper configuration settings for sources

- [x] 08.05.01 Ensure that a source has independent settings for enabling or disabling using readability on the feed's Content (from the rss feed), separate of using readability on the html scraping method (if enabled for a feed) (so a feed can have its content ingested raw (no readability), content processed with readability, or site scraped with readability enabled))

**Deliverable: Production-ready background processing that keeps manual and async flows in sync**
**Test: Trigger fetch/scrape from UI and scheduler, confirm shared logic enqueues jobs and surfaces status**

---

## Phase 09: Scheduler with Single Entry Point

**Goal: Flexible scheduling strategy**

### 09.01 Build Core Scheduler

- [x] 09.01.01 Create Scheduler.run entry point
- [x] 09.01.02 Find sources due for fetch (next_fetch_at <= now)
- [x] 09.01.03 Use SELECT FOR UPDATE SKIP LOCKED
- [x] 09.01.04 Enqueue FetchFeedJob for each due source
- [x] 09.01.05 Test scheduler finds and enqueues jobs

### 09.02 Restore Mission Control Dashboard

- [x] 09.02.01 Ensure Solid Queue is eagerly loaded and becomes the default Active Job adapter unless the host overrides it
- [x] 09.02.02 Install and run Solid Queue migrations for the dummy app so Mission Control can read queue data
- [x] 09.02.03 Override the Mission Control layout to force the light theme and load bundled assets correctly
- [x] 09.02.04 Verify Mission Control shows queue metrics/sections once Solid Queue is configured and a worker is running
- [x] 09.02.05 Capture the configuration updates in docs/notes so host apps understand the setup requirements

### 09.03 Configure Solid Queue Recurring Tasks

- [x] 09.03.01 Define recurring fetch/scrape jobs in `config/recurring.yml` using Solid Queue schedule syntax (class/args/command).
- [x] 09.03.02 Ensure `bin/jobs` loads the recurring schedule and document overriding it with `--recurring_schedule_file`.
- [x] 09.03.03 Explain how to disable recurring execution via `SOLID_QUEUE_SKIP_RECURRING` or `bin/jobs --skip-recurring`.
- [x] 09.03.04 Provide a hook to swap the default recurring job class for host-specific command execution.
- [x] 09.03.05 Verify recurring tasks enqueue expected jobs (integration/system coverage or supervised run script).

### 09.04 Refactor Job Queues card on dashboard to pull data directly from solid queue db tables, not from event metrics

- [x] 09.04.01 Implement a service/query that aggregates counts from Solid Queue job tables (ready, scheduled, failed, recurring).
- [x] 09.04.02 Update the dashboard card to render database-driven metrics and handle empty/paused queue states gracefully.
- [x] 09.04.03 Add automated coverage (unit + system) confirming the dashboard shows the new metrics.
- [x] 09.04.04 Document the metrics source change and required Solid Queue configuration/migrations for host apps.

## 09.05 Sources analytics

- [x] 09.05.01 add a heatmap histogram table visual showing how many sources have fetch intervals in which timespan buckets (5-30 minutes, 30-60, 60-120, 120-240, 240-480, 480+)
- [x] 09.05.02 Add a column to source index table showing new item rate per day to see how active different sources are

**Deliverable: Robust scheduling that works with standard Rails tools**
**Test: Run scheduler via rake task, verify jobs enqueued for due sources**

---

## Phase 10: Data Retention & Maintenance

**Goal: Manage data growth**

### 10.01 Add Retention Policies

- [x] 10.01.01 Implement retention by items_retention_days
- [x] 10.01.02 Implement retention by max_items per source
- [x] 10.01.03 Add UI controls for retention settings
- [x] 10.01.04 Document retention strategies

### 10.02 Build Cleanup Jobs

- [x] 10.02.01 Create ItemCleanupJob respecting retention policies
- [x] 10.02.02 Create LogCleanupJob for old fetch/scrape logs
- [x] 10.02.03 Add soft delete option for items
- [x] 10.02.04 Create rake tasks for manual cleanup
- [x] 10.02.05 Test cleanup jobs work correctly

**Deliverable: Sustainable data management with cleanup automation**
**Test: Run cleanup jobs, verify old data removed per policies**

---

## Phase 11: Host App Integration & Extensibility

**Goal: Hooks for host application customization**

### 11.01 Configuration DSL

- [x] 11.01.01 Create SourceMonitor.configure method
- [x] 11.01.02 Add HTTP client settings (timeouts, retries)
- [x] 11.01.03 Configure scraper adapters
- [x] 11.01.04 Set retention policies globally
- [x] 11.01.05 Document configuration options

### 11.02 Event System

- [x] 11.02.01 Add after_item_created callback hook
- [x] 11.02.02 Add after_item_scraped callback hook
- [x] 11.02.03 Add after_fetch_completed callback hook
- [x] 11.02.04 Support custom item processors
- [x] 11.02.05 Document event API with examples

### 11.03 Model Extensions

- [x] 11.03.01 Allow custom fields via table_name_prefix
- [x] 11.03.02 Support concerns for adding behavior
- [x] 11.03.03 Enable custom validations via config
- [x] 11.03.04 Provide STI examples for source types
- [x] 11.03.05 Create example app showing extensions

**Deliverable: Fully extensible for host application needs**
**Test: Create example host app with custom callbacks and fields**

---

## Phase 12: Real-time Updates with Turbo

**Goal: Live UI updates using Rails 8 defaults and Stimulus Components as documented in context7 mcp here: https://context7.com/stimulus-components/stimulus-components **

### 12.01 Add Turbo Streams

- [x] 12.01.01 Configure Turbo (included in Rails 8)
- [x] 12.01.02 Setup Turbo Stream broadcasts for fetch completion
- [x] 12.01.03 Stream new items to dashboard
- [x] 12.01.04 Update stats in real-time
- [x] 12.01.05 Test live updates in browser

### 12.02 Add Progress Indicators

- [x] 12.02.01 Show fetch status indicators per source on source index, updated with turbo streams
- [x] 12.02.03 Add loading states for async actions
- [x] 12.02.04 Toast notifications for manually initiated job completion (Stimulus Component: Notification)
- [x] 12.02.05 Real-time updates for source show when manually fetching
- [x] 12.02.06 Real-time updates for item show when manually fetching or scraping
- [x] 12.02.07 Test UX improvements

### 12.03 Add Stimulus Controllers

- [x] 12.03.03 Allow the search of items and feeds from their indexes (use ransack gem, documented in context7 mcp here: https://context7.com/activerecord-hackery/ransack)

## 12.04 Fetch Schedule

- [x] 12.04.01 When clicking a box in the fetch interval histogram table on source index, filter the list of sources to the ones that have that fetch interval
- [x] 12.04.02 On Dashboard, show an upcoming fetch schedule, grouped in 15 minute intervals for first hour, 30 minute intervals for hours 2-4, and then all remaining sources with intevals > 4 hours from current time. Show these as a stack of cards containing tables of the sources for each interval
- [x] 12.04.03 While on the Dashboard, as sources are fetched by the job queue, real-time update the upcoming fetch interval cards with turbo streams
- [x] 12.04.04 Make source fetch interval back off and speed up (based on if items are fetched) user configurable in the initalizer

**Deliverable: Modern real-time UI using Rails 8 defaults**
**Test: Trigger fetch, watch dashboard update in real-time**

---

## Phase 13: Advanced Error Recovery

**Goal: Self-healing system**

### 13.01 Implement Smart Retries

- [x] 13.01.01 Add retry strategies per error type
- [x] 13.01.02 Implement circuit breaker pattern
- [x] 13.01.03 Auto-adjust fetch intervals on failure
- [x] 13.01.04 Add manual retry from UI
- [x] 13.01.05 Test retry behavior

### 13.02 Source Health Monitoring

- [x] 13.02.01 Calculate rolling success rates
- [x] 13.02.02 Auto-pause failing sources after threshold (user configurable in initializer and per source)
- [x] 13.02.03 Add health status indicators in UI
- [x] 13.02.04 Auto-recovery detection and resume
- [x] 13.02.05 Test health monitoring

**Deliverable: Self-managing feed system with health monitoring**
**Test: Simulate failures, verify auto-pause and recovery**

---

## Phase 14: Performance Optimization

**Goal: Scale to thousands of sources**

### 14.01 Database Performance

- [x] 14.01.01 Verify all indexes from migrations
- [x] 14.01.02 Add missing indexes based on query analysis
- [x] 14.01.03 Optimize counter caches (items_count)
- [x] 14.01.04 Eliminate N+1 queries with includes
- [x] 14.01.05 Add query performance tests

**Deliverable: Handle 1000+ sources efficiently**
**Test: Load test with large number of sources, measure performance**

---

## Phase 16: Security Hardening & UX improvements

**Goal: Production security**

### 16.01 Input Validation

- [x] 16.01.01 Sanitize all user inputs
- [x] 16.01.05 Test security validations

### 16.02 Authentication & Authorization

- [x] 16.02.01 Integrate with host app auth (if configured)
- [x] 16.02.02 Add before_action filters for auth
- [x] 16.02.03 Test auth integration
- [x] 16.02.04 Verify CSRF protection active

### 16.03 Table sorting by columns

- [x] 16.03.01 Column headers in tables are clickable, flipping sort direction by asc and desc by the attribute for that column with arrows showing sort direction. use hotwire/turbo to refresh table upon column heading click without forcing full page reload
- [x] 16.03.02 Items index table default sorts by published timestamp desc
- [x] 16.03.03 move health monitoring card below source details sidebar card on source show view
- [x] 16.03.04 remove new source link from navbar
- [x] 16.03.05 show categories and tags on the item show view in the sidebar Item Details card
- [x] 16.03.06 Show categories and tags columns on the source show view in the items table
- [x] 16.03.07 source title should link to the source show page from the source index page table. View/Edit links per source row should be in a dropdown behind a gear icon (use dropdown from Stimulus Components as documented in context7 mcp here: https://context7.com/stimulus-components/stimulus-components)
- [x] 16.03.08 Move "View Original" and "Manual Scrape" buttons to be above the Content Comparison card to fix wrapping issues
- [x] 16.03.09 the title of each row in Recent Activity table on dashboard should link to the show view of that thing (fetch logs, scrape logs, items, etc)

**Deliverable: Enterprise-ready security**
**Test: Security scan with brakeman, verify protections**

---

## Phase 17: Complexity Analysis & Rails Conventions and Best Practices

**Goal: Simple, conventional implementations**

### 17.01 Comprehensive Complexity Audit

- [x] 17.01.01 Compile an inventory of all controllers, models, jobs, services, view components, and front-end assets to set audit scope
- [x] 17.01.02 Review controller actions for RESTful conventions, before_action bloat, and opportunities to slim controllers in favour of service objects
- [x] 17.01.03 Evaluate models, service objects, and modules for SRP adherence, duplication, and opportunities to encapsulate behaviour cleanly
- [x] 17.01.04 Inspect background jobs, Solid Queue workers, and scheduling flows for redundant logic, excessive coupling, or non-idiomatic patterns
- [x] 17.01.05 Audit front-end assets (Stimulus controllers, Turbo Streams, Tailwind, JS package management) for anti-patterns, dependency drift, or missing build steps
- [x] 17.01.06 Summarize complexity hotspots (long methods, deep conditionals, callback chains) with supporting metrics from tools like `bundle exec brakeman`, `bundle exec rubocop`, and SimpleCov trends and save to .ai/ folder as markdown file

### 17.02 Findings Report & Recommendations

- [x] 17.02.01 Produce an audit report cataloging each issue with file references, context, and impacted behaviour
- [x] 17.02.02 Document recommended Rails-aligned remediation for controller, model, job, and service object issues (RESTful routing, skinny controllers, fat models, dependency injection)
- [x] 17.02.03 Outline DRY and complexity reduction strategies (extractions, shared concerns, presenters) with implementation guidance and prerequisites
- [x] 17.02.04 Capture front-end package management and view-layer recommendations (Stimulus module boundaries, Turbo usage, asset bundling hygiene)
- [x] 17.02.05 Prioritize findings with effort/impact scoring, required stakeholders, and suggested sequencing across future roadmap phases
- [x] 17.02.06 Save final analysis to .ai/ folder as markdown file

### 17.03 Refactoring Execution Planning

- [x] 17.03.01 Break prioritized findings into actionable refactor workstreams (controllers, models/services, background jobs, front-end) with owners
- [x] 17.03.02 Define success criteria and regression test coverage requirements for each workstream, including new automated tests or fixtures needed
- [x] 17.03.03 Sequence refactor tasks into incremental deliveries, noting dependencies, rollout strategy, and migration considerations
- [x] 17.03.04 Establish monitoring and QA checkpoints (notifications, metrics dashboards, manual verification) to validate behavioural parity post-refactor
- [x] 17.03.05 Create follow-up tickets for any deferred or risky refactors, ensuring documentation links back to the audit report and recommendations

### 17.04 Controller & View Cleanup

- [x] 17.04.01 Extract a shared sanitized search helper and replace duplicated logic in sources, items, and logs controllers
- [x] 17.04.02 Introduce a shared pagination service (or Pagy adoption) with unit coverage and integrate into items index flows
- [x] 17.04.03 Create Turbo presenter/responder objects for notifications and details partial updates, updating controller actions accordingly
- [x] 17.04.04 Consolidate fetch and scrape log filtering into a shared concern with tests for query parameter casting and scopes
- [x] 17.04.05 Move analytics aggregation/bucketing logic out of `SourcesController#index` into a reusable query/presenter with dedicated tests

### 17.05 Service Decomposition

- [x] 17.05.01 Extract advisory lock management from `SourceMonitor::Fetching::FetchRunner` into a dedicated collaborator with unit tests
- [x] 17.05.02 Split fetch completion responsibilities (retention, scrape enqueue, events) into injectable services and cover with integration specs
- [x] 17.05.03 Refactor `SourceMonitor::Scraping::ItemScraper` into adapter resolver and persistence steps with contract tests for adapters
- [x] 17.05.04 Break `SourceMonitor::Items::RetentionPruner` strategies into separate classes/modules and expand test coverage for destroy vs soft delete
- [x] 17.05.05 Introduce a shared sanitization module for models (e.g., Source, future models) and migrate existing callbacks with unit coverage
- [x] 17.05.06 Extract reusable URL normalization helpers for Item and other URL-backed models with regression tests

### 17.06 Job & Scheduling Reliability

- [x] 17.06.01 Align `SourceMonitor::ScrapeItemJob` with shared state helpers, ensuring consistent pending/processing transitions and job tests
- [x] 17.06.02 Centralize cleanup job option parsing into a shared utility and update ItemCleanupJob/LogCleanupJob specs
- [x] 17.06.03 Add explicit retry/backoff policy for transient errors in `SourceMonitor::FetchFeedJob` with coverage for retry scheduling
- [x] 17.06.04 Instrument `SourceMonitor::Scheduler` runs and expose metrics/hooks verified by integration tests

### 17.07 Front-End Pipeline Modernization

- [x] 17.07.01 Convert Stimulus controllers to ES module/importmap loading and remove global registration, with smoke/system tests
- [x] 17.07.02 Provide graceful fallback when optional dropdown dependency is missing, including documentation and JS tests
- [x] 17.07.03 Replace or realign the transition shim with maintained stimulus-use utilities and verify behaviour via integration tests
- [x] 17.07.04 Automate Tailwind rebuilds and add asset verification scripts to the development/CI workflow

### 17.08 Tooling & Coverage Guardrails

- [x] 17.08.01 Establish Rubocop autocorrect baseline and enforce lint step in CI with developer documentation
- [x] 17.08.02 Add Brakeman to the bundle, configure ignore list if needed, and wire into CI security stage
- [x] 17.08.03 Enable SimpleCov with coverage gating (≥90% for new/changed lines) and surface reports in CI
- [x] 17.08.04 Add asset lint/test commands (e.g., eslint/stylelint or equivalent) and integrate into CI
- [x] 17.08.05 Update contributor docs with new lint/test workflows and ensure bin scripts support local runs

### 17.09 Dashboard Performance Enhancements

- [x] 17.09.01 Refactor `SourceMonitor::Dashboard::Queries` to batch/cache queries and separate routing/presentation concerns, with performance-focused tests
- [x] 17.09.02 Add instrumentation for dashboard query durations and expose metrics for Mission Control integration
- [x] 17.09.03 Document dashboard configuration expectations for host apps, including Mission Control linking prerequisites

---

## Phase 18: Documentation & Release

**Goal: Production-ready gem**

### 18.01 Complete Documentation

- [x] 18.01.01 Write comprehensive README
- [x] 18.01.02 Create installation guide
- [x] 18.01.03 Add API/configuration documentation
- [x] 18.01.04 Write deployment guides
- [x] 18.01.05 Create troubleshooting guide

### 18.02 Example Applications

- [x] 18.02.01 Create basic example app
- [x] 18.02.02 Add advanced integration example
- [x] 18.02.03 Show custom adapter example
- [x] 18.02.04 Include Docker configuration
- [x] 18.02.05 Document production deployment

**Deliverable: Production-ready, well-documented gem**
**Test: Install in fresh Rails 8 app using published gem**

---

## Phase 19: Admin UI Refinements

**Goal: Streamline source management workflows and centralize log visibility without adding complexity**

### 19.01 Surface Item Scraping Status on Source Detail

- [x] 19.01.01 Audit the source show item table partials to confirm which attributes are available for display and document the intended status states (pending, processing, success, failure, disabled)
- [x] 19.01.02 Update the item rows to render a scraping status badge/icon that reflects the latest `scrape_status` and gracefully handles items that have never been scraped
- [x] 19.01.03 Ensure Turbo/Hotwire updates push status changes in real time after scrapes complete, covering manual and background flows
- [x] 19.01.04 Add system coverage verifying that newly scraped items show the correct status badge and that status changes broadcast without full page reloads

### 19.02 Add "Scrape All" Control to Source Show

- [x] 19.02.01 Define UX placement, confirmation copy, and authorization expectations for a "Scrape All" button on the source detail page. Default to scraping all items on the current page of the table, with a radio button, and another option for "all unscraped items for this source ([count])" and also "All items (even those previously scraped) ([count])" that the user can toggle
- [x] 19.02.02 Wire the control to enqueue scraping for eligible items via the existing `SourceMonitor::Scraping::Enqueuer`, respecting auto-scrape settings and avoiding duplicate jobs
- [x] 19.02.03 Provide user feedback (flash/turbo partial) summarizing how many items were enqueued and expose errors when nothing qualifies
- [x] 19.02.04 Ensure the system allows per-source scraping rate limits so that the queue is properly metered to not denial of service the source to scrape their items
- [x] 19.02.05 Cover the new control with system and service tests, including a regression case for sources with no scrape-eligible items

### 19.03 Add Source Deletion from Index Table

- [x] 19.03.01 Specify the destructive action UX (button location, confirmation modal/text, tooltip) for deleting a source directly from the index list
- [x] 19.03.02 Implement the delete button using standard Rails RESTful routes, ensuring Turbo seamlessly removes the row and updates counters without full refreshes
- [x] 19.03.03 Validate that dependent records (items, logs, schedules) are handled according to existing retention/deletion rules and document any follow-up work
- [x] 19.03.04 Add controller and system tests covering successful deletion, cancellation, and unauthorized attempts

---

## Phase 20: Rails Convention & Architecture Cleanup

**Goal: Ensure entire codebase follows the rails way and is approachable and understandable**

**Reference:** Complete audit findings in `.ai/codebase_audit_2025.md`

**Total Estimated Effort:** 36-53 hours across 4 sub-phases

---

### 20.01 Critical Fixes - Phase 1 (8-12 hours)

**Reference:** `.ai/codebase_audit_2025.md:1203-1223`

**Priority:** MUST FIX - Immediate impact on code quality and performance

- [x] 20.01.01 **Refactor SourcesController destroy method** (2-3 hours) - Extract 61-line method into service object. Reference: `.ai/codebase_audit_2025.md:41-216` - Create `SourceMonitor::Sources::DestroyService` that handles deletion, query rebuilding, metrics recalculation, and returns Result object. Reduce controller method to <15 lines.
- [x] 20.01.02 **Extract BulkScrapeResultPresenter** (2-3 hours) - Extract 47-line flash message builder from controller. Reference: `.ai/codebase_audit_2025.md:941-1015` - Create `SourceMonitor::Scraping::BulkResultPresenter` that handles all message formatting logic. Testable without mocking view_context.
- [x] 20.01.03 **Create TurboStreamPresenter for sources** (2-3 hours) - Extract duplicated Turbo Stream response building. Reference: `.ai/codebase_audit_2025.md:90-215` - Create `SourceMonitor::Sources::TurboStreamPresenter` with methods for deletion, heatmap updates, empty state rendering. Consolidate 40+ lines of repeated logic.
- [x] 20.01.04 **Fix N+1 query in sources index** (1-2 hours) - Pre-calculate activity rates for all sources. Reference: `.ai/codebase_audit_2025.md:220-311` - Ensure `@item_activity_rates` hash contains entries for ALL sources in result set. Update view to never fall back to individual queries. Verify with query log that N+1 is eliminated.
- [x] 20.01.05 **Remove inline script from turbo_visit partial** (1-2 hours) - Replace inline JavaScript with Turbo Stream action. Reference: `.ai/codebase_audit_2025.md:313-389` - Create custom `StreamActions.redirect` function in `turbo_actions.js`. Update all usages of `_turbo_visit.html.erb` partial. Test CSP compliance.

**Acceptance Criteria:**

- SourcesController reduced from 356 lines to <200 lines
- All controller methods <20 lines
- Zero N+1 queries in sources#index (verify with bullet gem or query log)
- No inline `<script>` tags in views
- All tests passing

---

### 20.02 High-Impact DRY Violations - Phase 2 (12-16 hours)

**Reference:** `.ai/codebase_audit_2025.md:1226-1262`

**Priority:** HIGH - Significant maintainability impact

- [x] 20.02.01 **Replace default_scope anti-pattern in Item model** (4-6 hours) - Remove global default_scope for soft deletes. Reference: `.ai/codebase_audit_2025.md:391-452` - Remove `default_scope { where(deleted_at: nil) }`. Add explicit `.active` scope. Update Source associations to use `-> { active }` lambda. Update ALL Item queries in controllers/services to explicitly use `.active`. Update 7+ controller actions and 10+ service objects. Test thoroughly.
- [x] 20.02.02 **Create validates_url_format method in UrlNormalizable concern** (2-3 hours) - Eliminate 5 duplicated URL validation methods. Reference: `.ai/codebase_audit_2025.md:456-544` - Add `validates_url_format(*attributes)` class method to `lib/source_monitor/models/url_normalizable.rb`. Dynamically define validation methods. Update Source model to use `validates_url_format :feed_url, :website_url`. Update Item model to use `validates_url_format :url, :canonical_url, :comments_url`. Remove 5 manual validation methods.
- [x] 20.02.03 **Create Loggable concern for shared log behavior** (1-2 hours) - Consolidate FetchLog and ScrapeLog duplicated code. Reference: `.ai/codebase_audit_2025.md:548-626` - Create `app/models/concerns/source_monitor/loggable.rb` with shared validations, scopes, and attribute defaults. Include in both FetchLog and ScrapeLog models. Remove duplicated code from both models.
- [x] 20.02.04 **Create TurboStreamable concern for response building** (3-4 hours) - DRY up 50+ lines repeated 5+ times. Reference: `.ai/codebase_audit_2025.md:630-736` - **COMPLETE**: Phase 20.01 already created `SourceMonitor::Sources::TurboStreamPresenter` which adequately addresses the major duplication. Remaining duplication in `render_fetch_enqueue_response` and `respond_to_bulk_scrape` serves different purposes and doesn't warrant a generic concern. Presenter pattern is superior to a generic concern for these use cases.
- [x] 20.02.05 **Enhance SanitizesSearchParams with query building** (2-3 hours) - Consolidate ransack query setup. Reference: `.ai/codebase_audit_2025.md:740-824` - Add `searchable_with` class method accepting scope and default_sorts. Add `build_search_query` instance method. Update SourcesController and ItemsController to use new DSL. Remove duplicated ransack initialization code from 3+ locations. All duplication eliminated.
- [x] 20.02.06 **Add NOT NULL database constraints** (2-3 hours) - Enforce critical field constraints at DB level. Reference: `.ai/codebase_audit_2025.md:826-903` - Create migration to add NOT NULL constraints on `items.guid` and `items.url`. Write data cleanup script to handle existing nulls. Run migration and verify constraints applied. All constraints active.

**Acceptance Criteria:**

- ✅ All Item queries explicitly use `.active` scope
- ✅ Zero duplicated URL validation methods (5 removed)
- ✅ Zero duplicated log model code (FetchLog/ScrapeLog share concern)
- ✅ Turbo Stream response building addressed by Phase 20.01 presenter
- ✅ Ransack query setup uses DSL (no duplication)
- ✅ Database enforces NOT NULL on critical fields
- ✅ All tests passing (266 runs, 1147 assertions)

---

### 20.03 Medium Priority Improvements - Phase 3 (10-15 hours)

**Reference:** `.ai/codebase_audit_2025.md:1264-1286`

**Priority:** NICE TO HAVE - Quality of life improvements

- [x] 20.03.01 **Consolidate after_initialize callbacks** (1 hour) - Use Rails attribute API for defaults. Reference: `.ai/codebase_audit_2025.md:1016-1040` - In Source model, replace 3 `after_initialize` callbacks with `attribute :field, default: -> { value }` declarations. Remove `ensure_hash_defaults`, `ensure_fetch_status_default`, and `ensure_health_defaults` methods.
- [x] 20.03.02 **Convert due_for_fetch scope to class method** (30 min) - Scopes with variables should be class methods. Reference: `.ai/codebase_audit_2025.md:1042-1067` - Convert `scope :due_for_fetch, lambda { ... }` to `def self.due_for_fetch(reference_time: Time.current)`. Add explicit parameter. Update all callers.
- [x] 20.03.03 **Refactor routes to be more RESTful** (3-4 hours, OPTIONAL) - Non-RESTful custom member actions. Reference: `.ai/codebase_audit_2025.md:905-940` - Consider creating nested resource controllers: `SourceFetchesController`, `SourceRetriesController`, `SourceBulkScrapesController`. Evaluate effort vs benefit. Document decision. **Decision documented in `.ai/routes_refactor_evaluation.md` - DO NOT REFACTOR.**
- [x] 20.03.04 **Add Turbo Frame to search forms** (2 hours) - Search submissions trigger full page reloads. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Wrap search forms in Turbo Frame targeting results table. Add debounced search Stimulus controller. Test search without page reload.
- [x] 20.03.05 **Add Turbo Frame to pagination** (1 hour) - Pagination triggers full page reloads. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Add `data: { turbo_frame: "..." }` to pagination links. Test pagination without page reload. Optional: Add keyboard navigation (arrow keys).
- [x] 20.03.06 **Fix manual counter cache logic** (2 hours) - Manual counter updates are error-prone. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Wrap `soft_delete!` in transaction. Use `save!` instead of `update_columns`. Add `reset_items_counter!` method to Source. Test counter cache accuracy.
- [x] 20.03.07 **Tighten scrape_settings strong params** (1 hour) - Overly permissive nested parameters. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Explicitly permit only expected keys under `scrape_settings`: `{ selectors: [:content, :title], timeout: [], javascript_enabled: [] }`. Test rejected params.

**Acceptance Criteria:**

- ✅ Source model uses attribute API for defaults (3 callbacks removed)
- ✅ `due_for_fetch` is a class method with explicit parameters
- ✅ Routes refactoring evaluated and documented (decision: DO NOT REFACTOR)
- ✅ Search and pagination use Turbo Frames (no page reloads)
- ✅ Counter cache logic improved with `reset_items_counter!` method
- ✅ Strong params explicitly list allowed keys for scrape_settings
- ✅ All tests passing (280 runs, 1180 assertions)

---

### 20.04 RESTful Routes Refactor - Phase 4 (8 hours, OPTIONAL/DEFERRED)

**Reference:** `.ai/routes_refactor_evaluation.md`

- [x] 20.04.01 **Create nested resource controllers** (2 hours) - Extract member actions to dedicated controllers. Reference: `.ai/routes_refactor_evaluation.md:44-48` - Create `SourceFetchesController`, `SourceRetriesController`, `SourceBulkScrapesController`. Move action logic from SourcesController. Preserve all before_action filters and helper methods.
- [x] 20.04.02 **Update routes configuration** (1 hour) - Convert member actions to nested resources. Reference: `.ai/routes_refactor_evaluation.md:57-60` - Update `config/routes.rb` to use nested resource syntax: `resource :fetch, only: [:create]`, etc. Document route changes in CHANGELOG.
- [x] 20.04.03 **Update all view route helpers** (2 hours) - Update route helpers throughout views. Reference: `.ai/routes_refactor_evaluation.md:62-66` - Update all `link_to` and `button_to` calls from `fetch_source_path` to `source_fetch_path`. Update all Turbo Stream rendering. Update all redirect paths. Verify no broken links.
- [x] 20.04.04 **Update test suite for new routes** (2 hours) - Update controller and system tests. Reference: `.ai/routes_refactor_evaluation.md:68-72` - Create controller tests for 3 new controllers. Update integration tests. Update system tests. Update all route helper references. Ensure 100% test coverage maintained.
- [x] 20.04.05 **Testing and validation** (1 hour) - Verify behavioral parity. Reference: `.ai/routes_refactor_evaluation.md:74-81` - Run full test suite. Manual testing of fetch, retry, scrape_all actions. Verify Turbo Stream responses work correctly. Load test with 100+ sources. Document any behavioral changes.

**Acceptance Criteria:**

- 3 new nested resource controllers created
- All member actions converted to RESTful nested resources
- All view route helpers updated
- All tests passing with same coverage
- Zero behavioral changes (functional parity maintained)
- Documentation updated with route changes

**When to Reconsider (from evaluation):**

- Controllers grow beyond 300 lines (currently ~293 after Phase 20.01-20.02)
- New team members report confusion about action locations
- Need to add 5+ more custom actions
- Performance profiling shows controller bloat affecting response times

---

### 20.05 Polish & Optimization - Phase 5 (6-10 hours)

**Reference:** `.ai/codebase_audit_2025.md:1274-1286`

**Priority:** OPTIONAL - Performance and consistency improvements

- [x] 20.05.01 **Extract toast delay constants** (30 min) - Magic numbers scattered across controllers. Reference: `.ai/codebase_audit_2025.md:1105-1127` - Add `TOAST_DURATION_DEFAULT = 5000` and `TOAST_DURATION_ERROR = 6000` to ApplicationController. Create `toast_delay_for(level)` helper. Update all toast calls.
- [x] 20.05.02 **Clean up global event listener** (30 min) - Unused/unclear custom event. Reference: `.ai/codebase_audit_2025.md:1085-1103` - Document purpose of `feed-monitor:form-finished` event or remove if unused. Move to Stimulus controller if needed for cleanup. **Decision: Removed unused event listener.**
- [x] 20.05.03 **Rename log filtering methods** (1 hour) - Inconsistent naming conventions. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Rename `log_filter_status` to `status_filter`, `log_filter_item_id` to `item_id_filter`. Rename `filter_fetch_logs` to `apply_fetch_log_filters`. Use consistent verb/noun patterns.
- [x] 20.05.04 **Add performance indexes** (2-3 hours) - Missing indexes for common queries. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Create migration adding: `index_items_on_source_and_created_at_for_rates`, `index_sources_on_active_and_next_fetch` (partial), `index_sources_on_failures` (partial). Analyze query performance before/after.
- [x] 20.05.05 **Add check constraint on fetch_status enum** (1-2 hours) - Application-level validation only. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Create migration adding PostgreSQL CHECK constraint: `CHECK (fetch_status IN ('idle', 'queued', 'fetching', 'failed'))`. Test invalid status rejection at DB level.
- [x] 20.05.06 **Optimize dashboard queries with JOINs** (2-3 hours) - Subqueries less efficient than JOINs. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Refactor `SourceMonitor::Dashboard::Queries` correlated subqueries to use LEFT JOINs. Measure query performance improvement. Update `scrape_log_sql` and `item_sql` methods.
- [x] 20.05.07 **Simplify dropdown controller async import** (30 min, OPTIONAL) - Over-engineered progressive enhancement. Reference: `.ai/codebase_audit_2025.md:1069-1082` - Evaluate static import of stimulus-use vs dynamic import. Document trade-offs. Simplify if benefits outweigh loss of progressive enhancement. **Decision: Keep current implementation, documented reasoning in code.**

**Acceptance Criteria:**

- ✅ Toast delays use named constants (`TOAST_DURATION_DEFAULT`, `TOAST_DURATION_ERROR`)
- ✅ Helper method `toast_delay_for(level)` created and used throughout controllers
- ✅ Unused global event listener removed
- ✅ Method naming follows consistent verb/noun patterns (all renamed)
- ✅ Performance indexes added: `index_items_on_source_and_created_at_for_rates`, `index_sources_on_active_and_next_fetch`, `index_sources_on_failures`
- ✅ Database enforces fetch_status enum constraints with CHECK constraint
- ✅ Dashboard queries use LEFT JOINs instead of correlated subqueries
- ✅ Dropdown controller evaluated - decided to keep current implementation with documented reasoning
- ✅ All 283 tests passing with 1192 assertions

---

### 20.06 Fix and Optimize Front End asset management for engine

**Reference:** `.ai/engine-asset-configuration.md:11-188`

- [x] 20.06.01 **Audit current asset tooling and bundler deps** (2h) - Completed. Updated gemspec to include `cssbundling-rails`/`jsbundling-rails`, refreshed `package.json` scripts and dependencies. Reference: `.ai/engine-asset-configuration.md:11-28`.
- [x] 20.06.02 **Document current dummy app breakage** (1h) - Captured the missing Tailwind/JS failure mode and added troubleshooting guidance referencing the asset guide. Reference: `.ai/engine-asset-configuration.md:11-28`.
- [x] 20.06.03 **Plan asset directory realignment** (1.5h) - Namespaced builds, images, and svgs per guide recommendations. Reference: `.ai/engine-asset-configuration.md:32-44`.
- [x] 20.06.04 **Implement bundling pipeline setup** (3h) - Installed bundling toolchain via dummy app flow, established npm build/watch scripts, and added `SourceMonitor::Assets::Bundler`. Reference: `.ai/engine-asset-configuration.md:21-28`.
- [x] 20.06.05 **Expose asset paths via engine initializer** (1.5h) - Engine initializer now exposes builds/images/svgs for both pipelines. Reference: `.ai/engine-asset-configuration.md:48-76`.
- [x] 20.06.06 **Add Sprockets precompile automation** (2h) - Added programmable precompile list and tests covering Sprockets discovery. Reference: `.ai/engine-asset-configuration.md:79-113`.
- [x] 20.06.07 **Assess manifest fallback path** (optional, 1h) - Documented manifest fallback option in configuration docs; keeping programmatic approach as default. Reference: `.ai/engine-asset-configuration.md:114-143`.
- [x] 20.06.08 **Align asset usage in views/stylesheets** (1.5h) - Layout now loads bundled CSS/JS modules; controllers consume local imports. Reference: `.ai/engine-asset-configuration.md:147-167`.
- [x] 20.06.09 **Cross-pipeline verification** (2h) - Added automated coverage for asset exposure, verified Propshaft tests, and ensured Sprockets manifests precompile. Reference: `.ai/engine-asset-configuration.md:180-188`.
- [x] 20.06.10 **Document asset setup & troubleshooting** (1h) - README/config/troubleshooting now call out bundling steps and fallback guidance. Reference: `.ai/engine-asset-configuration.md:11-188`.

---

### 20.07 Additional Improvements - Phase 6 (Low Priority)

**Reference:** `.ai/codebase_audit_2025.md:1105-1127`

- [x] 20.07.01 **Consolidate `refreshed` variable naming** - Use `@source.reload` directly or be consistent. Reference: `.ai/codebase_audit_2025.md:1105-1127`
- [x] 20.07.02 **Document or simplify assign_content_attribute pattern** - Complex delegation logic may be candidate for concern if pattern repeats. Reference: `.ai/codebase_audit_2025.md:1105-1127`

**Deliverable for Phase 20:**

- SourcesController reduced from 356 lines to <150 lines
- 5 duplicated validation methods consolidated to 1 concern method
- Zero N+1 queries verified with bullet gem
- All inline scripts removed
- default_scope anti-pattern eliminated
- 50+ lines of Turbo Stream duplication consolidated
- Database constraints enforce data integrity
- Performance indexes added for common queries
- All tests passing (aim for >90% coverage on changed code)

**Testing Strategy for Phase 20:**

1. Run full test suite after each subtask
2. Use bullet gem to verify N+1 query elimination
3. Use query log to verify index usage
4. Run brakeman for security validation
5. Measure controller line count reduction
6. System tests for all Turbo Frame changes
7. Load test sources index with 100+ sources

---

## Phase 21: Log UX Improvements

**Goal: Consolidate Fetch & Scrape Logs to one unified UX**

### 21.01 Consolidate Fetch & Scrape Logs into a single viewing experience

- [x] 21.01.01 Inventory current fetch and scrape log views/partials to outline the combined layout, including shared columns and log-type specific metadata
- [x] 21.01.02 Design a unified log query object/presenter that supports filtering by log type, timeframe ranges, source selection, search terms, and pagination
- [x] 21.01.03 Implement the consolidated table/section in the UI with filter controls and ensure the controller accepts/validates the new params without duplicating logic
- [x] 21.01.04 Update instrumentation and documentation to reflect the merged log view and add automated coverage (unit + system) for filtering, searching, and pagination paths

**Deliverable: Source management UI exposes clear scraping controls and a single consolidated log explorer**
**Test: Drive the new controls via system specs to confirm status rendering, bulk scraping, deletions, and log filtering behave as expected**

---

## Phase 22: Release Readiness & Host Installation Experience

**Goal: Ship SourceMonitor as an installable gem with bulletproof host app onboarding**

### 22.01 Package Readiness Audit

- [x] 22.01.01 Review `source_monitor.gemspec` metadata, dependencies, and executables to match release expectations (homepage, changelog, docs URLs, Ruby/Rails version constraints)
- [x] 22.01.02 Establish semantic versioning policy and release cadence, updating `.ai/project_overview.md` and `CHANGELOG.md` with the release checklist
- [x] 22.01.03 Confirm gem build artifacts (`gem build source_monitor.gemspec`) exclude development-only files via `.gemspec` and `.npmignore`/`.gitignore` alignment

### 22.02 Fresh Host App Installation Flow

- [x] 22.02.01 Script a disposable Rails 8 host app harness (e.g., `tmp/host_app`) that installs the gem from the local path and exercises the install generator
- [x] 22.02.02 Add automated test suite (bin/rails test or RSpec) that boots the harness, runs `rails g source_monitor:install`, and asserts migrations/routes initializers mount without manual edits
- [x] 22.02.03 Verify host app retains existing configuration (environment settings, Solid Queue adapter, Action Cable config) by snapshotting before/after diffs in the harness tests

### 22.03 Isolation & Compatibility Guarantees

- [x] 22.03.01 Audit engine initializers, Railties, and configuration hooks to ensure they no-op when host overrides are present; document guard clauses or configuration fallbacks
- [x] 22.03.02 Add regression tests ensuring engine generators do not overwrite existing host files (e.g., `config/application.rb`, `config/cable.yml`), using temporary fixtures to simulate conflict scenarios
- [x] 22.03.03 Validate mounting options for varied host setups (API-only apps, custom queue_db, Redis Action Cable) and record support matrix in docs

### 22.04 Installation & Upgrade Documentation

- [x] 22.04.01 Produce a dedicated `docs/installation.md` (linked from README) covering Gemfile entry, bundle install, generator invocation, migrations, mount instructions, and Solid Queue prerequisites
- [x] 22.04.02 Update README quickstart and CHANGELOG release sections with step-by-step upgrade notes (engine migrations, configuration diffs, optional Mission Control integration)
- [x] 22.04.03 Draft troubleshooting guide for common install issues (missing Solid Queue tables, Tailwind build failures, mission_control-jobs not mounted) and cross-link from generator output

### 22.05 Release Pipeline & Quality Gates

- [x] 22.05.01 Create release automation task (e.g., `bin/release`) that runs the full set of quality gates (`bin/rubocop`, `bin/brakeman`, `bin/test-coverage`, `bin/check-diff-coverage`), builds the gem, and tags versions with an annotated changelog entry
- [x] 22.05.02 Expand CI with a release-verification job that installs the built gem into the disposable host app harness, runs the install generator and smoke tests, and reuses stored coverage to fail if diff coverage or harness assertions regress
- [x] 22.05.03 Document manual release verification in `.ai/release_checklist.md`, including checking coverage artifacts/baseline freshness, gem size, README rendering on RubyGems, and confirmation that `bin/release` + the release-verification job both passed

### 22.06 Failure Recovery Experience

- [x] 22.06.01 Replace failing/auto-paused status badges with dropdown triggers (sources index + show) that expose recovery actions alongside concise helper copy, wired up with Turbo streams.
- [x] 22.06.02 Hook existing "Fetch Now" runner into a dropdown action that queues a full fetch, swaps the badge for an inline `Processing` state with spinner, and emits a toast confirmation via Turbo.
- [x] 22.06.03 Add a lightweight health-check job that enqueues through Solid Queue, performs a single fetch request without mutating items, records a dedicated log entry, and surfaces completion through the shared inline + toast UI.
- [x] 22.06.04 Implement "Reset to Active Status" for auto-paused sources to clear pause/backoff timestamps, failure counters, last error metadata, and restore the next fetch interval using source-level override or global default.
- [x] 22.06.05 Expand system/unit coverage to exercise dropdown UX, Turbo responses, log visibility, and state-reset behaviors for both failing and auto-paused sources.

**Deliverable: Operators can recover failing or auto-paused sources inline with Turbo-powered dropdowns, clear state resets, and auditable logs.**
**Test: System tests assert badge-to-dropdown flow, spinner/toast feedback, health-check log visibility, and reset-side effects on source scheduling.**

**Deliverable: Engine publishes as a gem with automated host app install verification, zero configuration bleed, and clear onboarding docs**
**Test: Release pipeline builds the gem, CI installs it into a fresh Rails 8 host app, and generator-driven smoke tests pass without modifying host configurations**

---

## Success Criteria Per Phase

Each phase must:

1. **Install cleanly** in a fresh Rails 8 app
2. **Not break** existing functionality
3. **Be testable** via automated tests
4. **Be usable** immediately via UI or console
5. **Add tangible value** that can be demonstrated

---

## Phase 23: Test Suite Performance Guardrails

- [x] 23.01 Add TestProf tooling and helpers for Minitest (TagProf, EventProf, StackProf, setup_once support)
- [x] 23.02 Optimize slow integration/lib suites, introduce smoke test target, and remove redundant DB writes
- [x] 23.03 Automate profiling in CI with guardrails and document contributor guidelines

## Testing Strategy

- **Unit Tests**: Every service, model, job
- **Integration Tests**: Full workflows with VCR
- **System Tests**: UI interactions with Capybara
- **Contract Tests**: Adapter interfaces
- **Performance Tests**: Benchmarks for large datasets

## Key Design Principles

1. **Rails 8 Native**: Use Rails 8 defaults (Solid Queue, Solid Cache, Turbo)
2. **Minimal Dependencies**: Tailwind + essential gems only
3. **Thin Vertical Slices**: Each phase is immediately testable
4. **Progressive Enhancement**: Start simple, add features incrementally
5. **Host App Extensibility**: Hooks for customization without forking
6. **Production Ready**: Security, performance, and observability built-in
