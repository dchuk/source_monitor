# Phase 17.02 Complexity Findings Report (2025-10-12)

## 1. Issue Catalog

### Controllers
- **Duplicated parameter sanitization** — `app/controllers/source_monitor/items_controller.rb:120` and `app/controllers/source_monitor/sources_controller.rb:172` both implement identical `sanitized_search_params`; keeping these in each controller risks divergence in future filters.
- **Manual pagination and query orchestration** — `app/controllers/source_monitor/items_controller.rb:13-33` mixes pagination math, search setup, and view state assembly, crowding the action and duplicating paging behaviour elsewhere.
- **Inline analytics aggregation** — `app/controllers/source_monitor/sources_controller.rb:11-27` performs distribution bucketing and analytics queries in-controller, making the action heavy and difficult to unit test.
- **Turbo Stream composition embedded in controllers** — `app/controllers/source_monitor/items_controller.rb:38-83` and `app/controllers/source_monitor/sources_controller.rb:140-168` contain sizeable arrays of Turbo Stream operations; changes to toast behaviour or DOM IDs now require controller edits.
- **Parallel filter logic in logs controllers** — `app/controllers/source_monitor/fetch_logs_controller.rb:5-23` and `app/controllers/source_monitor/scrape_logs_controller.rb:5-45` share similar scoping patterns but diverge in parameter casting, inviting subtle inconsistencies.

### Models & Services
- **`SourceMonitor::Source` doing too much** — `app/models/source_monitor/source.rb:20-150` handles sanitization, URL normalization, defaulting, and health thresholds; the breadth complicates reuse of sanitization rules by other models.
- **`SourceMonitor::Item` URL normalization** — `app/models/source_monitor/item.rb:52-133` embeds URL parsing logic; other URL-backed models cannot reuse the behaviour without duplication.
- **`Fetching::FetchRunner` orchestration sprawl** — `lib/source_monitor/fetching/fetch_runner.rb:39-186` owns locking, state transitions, retention pruning, scrape enqueueing, retry scheduling, and instrumentation dispatch in one class.
- **`Scraping::ItemScraper` responsibilities** — `lib/source_monitor/scraping/item_scraper.rb:28-200` combines adapter discovery, HTTP metadata handling, persistence, logging, and event publication within a single method flow.
- **`Items::RetentionPruner` strategy branching** — `lib/source_monitor/items/retention_pruner.rb:21-162` interleaves strategy selection with batch execution and counter maintenance, making soft-delete vs destroy paths harder to evolve.
- **Dashboard query coupling** — `lib/source_monitor/dashboard/queries.rb:17-87` fires multiple fresh queries for every request without caching or batching, and mixes routing helpers with aggregation logic.

### Jobs, Workers, Scheduling
- **Limited retry semantics** — `app/jobs/source_monitor/fetch_feed_job.rb:5-19` rescues only concurrency errors; transient network failures rely on defaults rather than an explicit retry/backoff plan.
- **State updates inside jobs** — `app/jobs/source_monitor/scrape_item_job.rb:25-45` issues `update_columns` inside locks; behaviour overlaps with `Scraping::Enqueuer`, risking drift between enqueue-time and job-time state handling.
- **Duplicated option normalization** — `app/jobs/source_monitor/item_cleanup_job.rb:18-69` and `app/jobs/source_monitor/log_cleanup_job.rb:18-71` repeat the same option-shaping logic, increasing maintenance costs as CLI flags expand.
- **Scheduler blind spots** — `lib/source_monitor/scheduler.rb:7-49` enqueues fetches but emits no instrumentation or metrics, limiting observability when schedule gaps occur.

### Front-End Assets
- **Global Stimulus registration** — `app/assets/javascripts/source_monitor/application.js:1-32` depends on global `window.Stimulus`, diverging from modern ES module patterns and risking double registration.
- **Fragile dropdown dependency** — `app/assets/javascripts/source_monitor/controllers/dropdown_controller.js:1-14` assumes `window.StimulusDropdown` exists; missing UMD bundle breaks dropdowns without fallback.
- **Transition shim divergence** — `app/assets/javascripts/source_monitor/dropdown_transition_shim.js:1-24` implements a custom `useTransition` that may fall behind the upstream library API.
- **Compiled Tailwind artefact** — `app/assets/builds/tailwind.css` (~1.4k lines) is committed without guardrails ensuring regeneration during releases.
- **No asset linting/build verification** — no scripted checks ensure controllers or Tailwind bundles stay current, leaving runtime errors undetected until manual testing.

### Tooling Gaps
- **Rubocop violations** — `bundle exec rubocop --format offenses` reports 366 issues (352 auto-correctable spacing offenses), indicating style drift.
- **Brakeman absent from bundle** — Running `bundle exec brakeman` fails because the gem is not declared; security checks are currently blocked.
- **No coverage tracking** — `test/test_helper.rb` lacks SimpleCov hooks, so coverage regressions are invisible.

## 2. Recommended Remediation (Controllers, Models/Services, Jobs)
- **Controllers**: Extract shared parameter sanitization and pagination into concerns or service objects; move analytics aggregation into query objects; introduce presenters/responders for Turbo Stream responses.
- **Models/Services**: Create reusable sanitization utilities (e.g., `SourceMonitor::Sanitization`), encapsulate URL normalization in a dedicated module, break `FetchRunner` into concurrency, state, and follow-up collaborators, and separate `ItemScraper` responsibilities into adapter resolver, persistence handler, and logger.
- **Jobs**: Align enqueue/job state transitions by reusing shared helpers, define custom retry strategies for transient errors, centralize option parsing for cleanup jobs, and instrument scheduler runs with metrics events.

## 3. DRY & Complexity Reduction Strategies
1. **Shared sanitization & normalization modules** — Provide mixins for parameter and URL sanitation to reuse across controllers and models.
2. **Pagination abstraction** — Introduce a pagination service or adopt Pagy/Kaminari to eliminate manual offset math across controllers.
3. **Command objects for Turbo responses** — Wrap Turbo Stream payload assembly in dedicated builders for reuse between controllers and tests.
4. **Service decomposition** — Apply single-responsibility classes (lock manager, retention handler, scrape enqueuer) to reduce the size and branching of core orchestration services.
5. **Instrumentation helpers** — Centralize logging/instrumentation patterns to avoid duplicating JSON payload composition across jobs and services.

## 4. Front-End Package & View-Layer Recommendations
- Migrate Stimulus controllers to modules (ESBuild or Importmap) while keeping a compatibility shim until host apps adopt the bundle.
- Provide defensive checks or progressive enhancement fallbacks when optional UMD dependencies (e.g., `StimulusDropdown`) are missing.
- Replace the custom transition shim with the maintained `@hotwired/stimulus-use` package or document divergence to keep behaviour in sync.
- Add a lightweight asset build verification step (e.g., `bin/rails test:assets` or `yarn lint`) and document Tailwind rebuild requirements in contributor guides.
- Audit Turbo Stream partials to ensure DOM IDs referenced in controllers are declared in a single presenter to avoid coupling across views.

## 5. Prioritization & Sequencing
| Issue | Area | Effort | Impact | Priority |
| --- | --- | --- | --- | --- |
| Decompose `FetchRunner` responsibilities | Fetching services | Medium | High | P1 |
| Shared controller sanitization/pagination helpers | Controllers | Low | High | P1 |
| Align Scraping enqueue vs job state handling | Jobs/Services | Medium | High | P1 |
| Formalize Stimulus asset pipeline | Front-end | Medium | Medium | P2 |
| Consolidate cleanup job option parsing | Background jobs | Low | Medium | P2 |
| Introduce Rubocop/Brakeman & coverage baselines | Tooling | Low | Medium | P2 |
| Replace `ItemScraper` adapter/persistence monolith | Scraping services | High | High | P1 |
| Dashboard query caching | Dashboard | Medium | Medium | P3 |
| Tailwind rebuild automation | Front-end | Low | Medium | P2 |

P1 items should seed Phase 17.03 workstreams; P2 items follow once shared utilities exist; P3 items can ride along with subsequent dashboard improvements.

## 6. Deliverables
- Saved this findings report at `.ai/phase_17_02_complexity_findings_2025-10-12.md`.
- Source material cross-referenced with Rails controller best practices from the official guides.
