**Context**

- This task implements the Confirm step of the OPML Import Wizard and the background import job for SourceMonitor.
- Upstream work (wizard shell, OPML parsing, preview/selection, health checks, bulk settings) will have populated an ImportSession record containing parsed_sources, selected_source_ids and bulk_settings.
- The engine already uses Solid Queue for background jobs, Turbo Streams for realtime UI updates, and has existing source creation logic and Turbo broadcast/responders to follow.

**Goals**

- Render a Confirm step view that shows a final summary: the list of selected sources to be imported and the bulk settings that will be applied.
- When the user confirms, enqueue a background import job (Solid Queue / ActiveJob) that:
  - Iterates selected sources, creates sources individually (reusing the engine’s existing source creation logic/service where available).
  - Records per-source outcomes: successes, failures (with error details), and skipped duplicates (feed URL match).
  - Persists an ImportHistory AR record containing imported_sources, failed_sources, skipped_duplicates, bulk_settings, started_at, completed_at, and reference to the performing user (integer user_id).
  - Handles idempotency/races (e.g., ActiveRecord::RecordNotUnique) and records appropriate skipped/failed state.
- Broadcast import completion via Turbo Streams so a static confirmation (counts and a table of failures) is visible on the Sources index; persist ImportHistory so the confirmation is queryable on subsequent visits.

**Technical Guidelines**

- Models & DB
  - Add ImportHistory ActiveRecord model + migration.
    - Use Rails default integer primary keys and integer user reference: e.g. t.references :user, foreign_key: true (integer FK).
    - Columns: imported_sources (jsonb), failed_sources (jsonb), skipped_duplicates (jsonb), bulk_settings (jsonb), started_at (t.datetime), completed_at (t.datetime), created_at/updated_at.
    - Index created_at for query performance.
  - Do not change existing sourcemon_sources table schema. Duplicate detection must use feed_url matching against that table.

- Background Job
  - Implement an import ActiveJob under app/jobs/source_monitor/import_opml_job.rb (or similar) that uses the Solid Queue adapter (follow existing job naming/queue conventions in repo).
  - Job responsibilities:
    - Load ImportSession or be supplied with the ImportSession id and ImportHistory id to update status.
    - Persist started_at at job start and completed_at at finish to the ImportHistory record.
    - For each selected parsed source:
      - Skip any source that already exists by exact feed_url match — mark as skipped duplicate and include feed_url and reason in skipped_duplicates.
      - Attempt to create the source by calling the engine’s existing source-creation service/object (discover and reuse service; do NOT reimplement creation logic in the job).
      - On successful create: append a concise representation (id, feed_url, title) to imported_sources.
      - On exception:
        - If ActiveRecord::RecordNotUnique (race / concurrent import), treat as skipped duplicate (record to skipped_duplicates) rather than failure.
        - Otherwise, record failure with feed_url, error class and message in failed_sources.
      - Ensure partial failures do not stop processing of remaining sources; process all selected sources and collect per-source results.
    - Save ImportHistory with final arrays and timestamps.
  - Job must be idempotent for retries: detect already-created feed_url and avoid creating duplicates.
  - Use transactions cautiously: individual source creations may be wrapped in their own transaction so one source failure doesn’t roll back the whole batch.

- Controller & Confirm Step
  - Add Confirm step controller action(s) to the wizard controller that:
    - Renders summary table of ImportSession.selected_source_ids joined with ImportSession.parsed_sources to show feed_url, title, and applied bulk_settings.
    - On confirm POST, create an ImportHistory record (with user reference and bulk_settings), enqueue the import job (passing ImportSession id and ImportHistory id), and return an immediate Turbo Stream/html response that redirects user back to the Sources index (or shows a confirmation note).
    - Enforce admin-only access using the engine’s existing authentication hooks (follow existing controller patterns; e.g., inherit SourceMonitor::ApplicationController and use configured authentication).
    - Sanitize permitted params as per engine conventions.

- Broadcasting & UI persistence
  - When job completes, broadcast a Turbo Stream message so the Sources index can render a static confirmation section (counts and failures).
    - Reuse engine’s existing broadcasting patterns (lib/source_monitor/realtime/* and lib/source_monitor/turbo_streams/stream_responder.rb) — create a suitable Turbo Stream target (e.g., turbo_stream_from "source_monitor_import_histories" or reuse "source_monitor_sources") and broadcast a partial that renders ImportHistory summary.
  - Ensure the ImportHistory record itself is persisted and can be queried from the Sources index UI (Sources index should be able to list recent ImportHistory entries). For this task: ensure ImportHistory model, migration and broadcast exist; UI change for Sources index to consume ImportHistory should read from ImportHistory.where(user: current_user). Order and exact UI placement follow engine conventions.

- Error handling & idempotency
  - Duplicate detection must be feed_url exact match against sourcemon_sources before attempting create; handle race conditions (RecordNotUnique) gracefully by recording skipped_duplicates.
  - For any unexpected exceptions record error_class, error_message and minimal backtrace (if desired) in failed_sources; do not leak raw exceptions to clients—render error details in admin UI only.
  - Ensure the import job cannot create duplicate sources if it is run multiple times (use pre-check + rescue RecordNotUnique).

- Conventions & Integration
  - Follow existing Rails engine patterns: controllers respond to HTML and turbo_stream, use Turbo Frames for partial updates, Tailwind styling, accessibility.
  - Use Solid Queue / ActiveJob consistent queue naming conventions (look up SourceMonitor.config.queue_name_for or existing job classes to match queue naming).
  - Use strong parameter sanitization utilities already present in the engine (SourceMonitor::Security::ParameterSanitizer or controller helpers).
  - Tests: add unit/functional tests for ImportHistory model and job behavior, and a system/controller test covering confirm POST enqueuing job and final persisted ImportHistory.

**Out of scope**

- Implementing or modifying Preview/Upload/Health steps (assume ImportSession contains necessary state).
- Per-feed settings overrides (bulk settings apply uniformly).
- Real-time progress bar for the import job (only final completion broadcast and static confirmation required).
- Advanced retry/recovery logic for failed imports beyond basic idempotency and recording errors.
- Large-scale UI redesign—only add Confirm step view and ensure Sources index can display ImportHistory entries.

**Suggested research (files/areas to inspect before implementing)**

- Controller patterns and Turbo Stream responders:
  - app/controllers/source_monitor/sources_controller.rb
  - lib/source_monitor/turbo_streams/stream_responder.rb
  - any existing controllers that render summary/confirmation messages
- Background job examples and Solid Queue usage:
  - app/jobs/source_monitor/* (FetchFeedJob, ScrapeItemJob) and how they declare queues
  - lib/source_monitor/jobs/solid_queue_metrics.rb and job conventions
- Real-time broadcasting patterns:
  - lib/source_monitor/realtime/broadcaster.rb
  - lib/source_monitor/dashboard/turbo_broadcaster.rb
- ImportSession usage and fields:
  - the ImportSession model and where parsed_sources, selected_source_ids, bulk_settings are stored (migration and model file from ImportSession task)
- Source creation logic/service objects:
  - app/controllers/source_monitor/sources_controller.rb#create and any service objects under lib/source_monitor or app/services related to creating a Source (prefer reuse)
- Tests demonstrating handling of ActiveRecord::RecordNotUnique or duplicate create patterns (see item creation duplicates in lib/source_monitor/items/item_creator.rb for pattern)

Use the repository’s existing patterns and helpers; do not introduce new auth/permission systems—leverage engine’s existing admin-only checks and Turbo Stream broadcasting conventions.