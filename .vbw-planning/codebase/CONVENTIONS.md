# Conventions

## Ruby Code Style

- **Style Guide**: Rails Omakase via `rubocop-rails-omakase` gem
- **Frozen String Literals**: Consistently used across all app/ and lib/ Ruby files (`# frozen_string_literal: true`)
- **No frozen_string_literal**: Absent from some test files and the main `lib/source_monitor.rb` entry point

## Naming Conventions

### Module/Class Naming
- All engine code namespaced under `SourceMonitor::`
- Sub-modules use descriptive domain names: `Fetching`, `Scraping`, `Health`, `Security`, `Dashboard`, `Realtime`
- Service objects named as nouns (e.g., `FeedFetcher`, `ItemScraper`, `Scheduler`, `RetentionPruner`)
- Presenters suffixed with `Presenter` (e.g., `BulkResultPresenter`, `RecentActivityPresenter`, `TurboStreamPresenter`)
- Query objects in `analytics/` and `dashboard/` (e.g., `Queries`, `SourcesIndexMetrics`)

### File Organization
- One class per file, file path mirrors class namespace
- Nested classes extracted to sub-directories (e.g., `item_scraper/adapter_resolver.rb`, `item_scraper/persistence.rb`)
- Concerns placed in `concerns/` subdirectories

### Database Naming
- Table prefix: `sourcemon_` (configurable via `config.models.table_name_prefix`)
- Tables: `sourcemon_sources`, `sourcemon_items`, `sourcemon_fetch_logs`, etc.
- Foreign keys follow Rails conventions: `source_id`, `item_id`
- Timestamps use `started_at`/`completed_at` pattern for log records

### Method Naming
- Bang methods (`!`) for operations that raise on failure: `soft_delete!`, `mark_processing!`
- Predicate methods: `fetch_circuit_open?`, `auto_paused?`, `deleted?`, `success?`
- `call` method pattern for service objects and scraper adapters
- Private `set_*` for controller before_actions: `set_source`, `set_import_session`

### Job Naming
- Jobs suffixed with `Job`: `FetchFeedJob`, `ScrapeItemJob`, `ScheduleFetchesJob`
- Queue assignment via `source_monitor_queue :fetch` class method

### Controller Naming
- Resource controllers follow Rails conventions: `SourcesController`, `ItemsController`
- Singular nested resource controllers: `SourceFetchesController`, `SourceRetriesController`
- Action-specific controllers for non-RESTful actions: `SourceBulkScrapesController`, `SourceHealthChecksController`

## Configuration Patterns

- Configuration via `SourceMonitor.configure { |config| ... }` block DSL
- Nested configuration objects with `reset!` methods for testing
- Settings classes with explicit defaults defined as constants
- Callable values supported (procs/lambdas) for dynamic configuration

## Error Handling

- Custom error hierarchy: `FetchError` base with typed subclasses (`TimeoutError`, `ConnectionError`, `HTTPError`, `ParsingError`)
- Errors carry structured data: `http_status`, `response`, `original_error`
- Defensive `rescue StandardError` wrappers around logging calls
- `Rails.logger` usage guarded with `defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger`

## Struct Usage

- `Struct.new(..., keyword_init: true)` extensively used for result/event objects
- Named structs: `Result`, `ResponseWrapper`, `EntryProcessingResult`
- Event structs: `ItemCreatedEvent`, `ItemScrapedEvent`, `FetchCompletedEvent`

## Frontend Conventions

- CSS scoped under `.fm-admin` class with Tailwind `important` selector
- Stimulus controllers registered on `window.SourceMonitorStimulus`
- Controller naming: kebab-case in HTML (`async-submit`, `confirm-navigation`)
- ERB partials prefixed with underscore, organized per resource
- Turbo Stream responses via `SourceMonitor::TurboStreams::StreamResponder`

## View Conventions

- Layouts: Engine uses host app layout; views are ERB
- Partials extensively used: `_row.html.erb`, `_details.html.erb`, `_form_fields.html.erb`
- Wizard steps as separate partials: `steps/_upload.html.erb`, `steps/_preview.html.erb`
- Toast notifications broadcast via realtime system

## Test Conventions

- Minitest with Rails test helpers (not RSpec)
- Test files mirror source structure: `test/lib/source_monitor/scraping/item_scraper_test.rb`
- Test helper methods: `create_source!` factory method in `ActiveSupport::TestCase`
- Parallel test execution by default
- Configuration reset in `setup` block: `SourceMonitor.reset_configuration!`
- WebMock disables external connections
- VCR for HTTP interaction recording
- test-prof `before_all` for expensive shared setup
- `with_inline_jobs` and `with_queue_adapter` helpers for job testing

## Documentation Conventions

- YARD-style comments in some service classes
- Inline comments explain "why" not "what"
- `# :nocov:` markers for untestable/defensive code paths
- CHANGELOG maintained in conventional format
- CONTRIBUTING.md present
