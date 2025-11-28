**Context**

- User story: "Health Check for Selected Sources" within the OPML Import Wizard. This Health Check step runs a health check for each selected parsed source, shows live results, and updates selection state before import.
- Tech brief: health checks must be enqueued as individual Solid Queue jobs, results persisted back into ImportSession.parsed_sources (fields: health_status, error), and updates broadcast in real-time via Turbo Streams. ImportSession uses a standard integer user_id and persists wizard state (parsed_sources, selected_source_ids, current_step, etc.).
- Existing codebase patterns to follow: Solid Queue job patterns (app/jobs/*), existing source health check logic and controller (source_health_checks_controller), realtime broadcasters (lib/source_monitor/realtime/broadcaster.rb), and Turbo Stream / Turbo Frame UI conventions (lib/source_monitor/turbo_streams/stream_responder.rb).

Goals

- Enqueue one Solid Queue health-check job per selected source when the Health Check step starts.
- Persist per-source health results into ImportSession.parsed_sources (add/ensure fields health_status and error).
- Broadcast row-level updates and an overall progress update (completed / total) in real time via Turbo Streams so the Health Check step UI updates as jobs complete.
- Unselect sources deemed unhealthy by default while allowing the user to re-select them; ensure selection state persists in ImportSession.selected_source_ids.
- Prevent navigation forward if no healthy sources remain selected (unless the user intentionally re-selects unhealthy ones).
- Implement server-side cancellation semantics so jobs do not update or broadcast for an expired/cancelled ImportSession.

Technical Guidelines

- Job orchestration
  - Enqueue a Solid Queue job per selected parsed source. Job payload must include at minimum: import_session_id and an identifier for the parsed source (index or parsed_source_id/UUID as stored in ImportSession.parsed_sources).
  - Reuse existing feed health check logic where available (inspect source_health_checks controller / health-check service used elsewhere) rather than reimplementing HTTP/Feed checks.
  - Name or implement the job in line with existing job conventions (app/jobs/source_monitor/*). The job should:
    - Load the ImportSession (guard by integer user_id scope).
    - Verify the ImportSession still exists and is in the Health Check step (or has a health_checks_active flag). If the session has been cancelled/expired, exit without broadcasting.
    - Run the health check for the feed URL.
    - Persist result into ImportSession.parsed_sources for the specific parsed entry: set health_status (values: healthy/unhealthy/unknown) and error (string or nil).
    - Update ImportSession.selected_source_ids to remove/unselect the entry if health_status == unhealthy (so UI reflects unselected by default). Do not destroy historical parsed data.
    - Broadcast a Turbo Stream update for the row and a progress update (completed count) after persisting.

- Persistence and data model
  - Store health results inside ImportSession.parsed_sources entries (JSONB). Each parsed source entry must include:
    - id/key (must be addressable by job),
    - feed_url (used for duplicate detection),
    - health_status (nullable string enum),
    - health_error (nullable text).
  - Selection state must be authoritative in ImportSession.selected_source_ids (JSONB array of parsed entry ids). Health job changes must update that array atomically (transaction).
  - Ensure ImportSession model uses integer user_id references per the tech brief.

- Broadcast / UI contract
  - Use Turbo Streams for all live updates. Follow existing engine broadcaster/presenter patterns:
    - Broadcast a row replacement partial (Turbo Stream) for the specific parsed source row showing updated health_status icon and selection checkbox state.
    - Broadcast a separate Turbo Stream or stream fragment with overall progress (completed / total). The progress UI in the Health Check view should subscribe to this stream.
  - Choose a Turbo stream target scope tied to the ImportSession (e.g., stream name or DOM target that includes import_session id) so updates only reach the appropriate wizard instance. Ensure consistent naming with other engine broadcasters.
  - Keep UI updates non-destructive: rows should preserve user ability to re-select unhealthy sources.

- UI-side behavior to enforce
  - After a health check job marks a source unhealthy, the UI must show it as unselected by default and display the error inline on the row (tooltip or error cell) while permitting re-selection.
  - The progress indicator must show completed / total and update as job results arrive.
  - Navigation to the next step must be disabled when selected healthy sources count is zero. Re-enabling should occur when the user re-selects at least one source manually.

- Cancellation semantics
  - When the user navigates away from the Health Check step or cancels the wizard, mark the ImportSession (e.g., set health_checks_active: false or current_step != 'health_check'). HealthCheck jobs must check this flag and not broadcast or mutate UI-visible session state if the session is no longer active.
  - Jobs may still persist logs/errors for auditing but must not broadcast to the now-expired wizard UI.

- Concurrency and safety
  - Jobs updating ImportSession should be resilient to concurrent updates: use transactions and row-level locking (or optimistic update with retries) to modify parsed_sources and selected_source_ids safely.
  - Handle cases where a duplicate source is discovered or a source is removed from selected_source_ids mid-check gracefully: persist the health result but ensure selected_source_ids and UI state remain consistent.

- Follow SourceMonitor conventions
  - Adhere to engine style: controller and job naming, Solid Queue enqueue patterns, Turbo Stream rendering, Tailwind/Turbo Frame based partials, accessibility.
  - Enforce admin-only access around enqueuing health checks via existing authentication hooks.
  - Strong-params/sanitization for any controller endpoints that trigger health checks or cancel them.

Out of scope

- Implementing retry logic for failed health checks (explicitly out of scope in PRD).
- Building or changing the visual design of the Health Check UI beyond status icon/error and progress updates.
- Global realtime channel/refactor: use engine broadcaster patterns rather than introducing an unrelated pubsub mechanism.
- Changes to sourcemon_sources table or source creation logic—duplicate detection remains feed-URL-only and uses existing source records.

Suggested research

- Inspect existing health check code and controller:
  - app/controllers/source_monitor/source_health_checks_controller.rb (how single-source health checks are performed and broadcast).
  - Any health-check services used for per-source health (search for "health" related services or logs).
- Review Solid Queue job patterns used in repo for enqueueing and job implementation:
  - app/jobs/source_monitor/* (FetchFeedJob, ScrapeItemJob) for job structure, error handling, and broadcasting style.
- Review realtime/Turbo broadcaster and stream responder conventions:
  - lib/source_monitor/realtime/broadcaster.rb
  - lib/source_monitor/turbo_streams/stream_responder.rb
  - existing Turbo stream presenters for row updates (e.g., sources presenters under lib/*).
- Inspect ImportSession model and migration (app/models/source_monitor/import_session.rb or equivalent) to confirm parsed_sources and selected_source_ids shapes and keys used to address parsed entries.
- Find existing wizard/ImportSession views or step partials to see expected Turbo Frame names and where to render row partials and the progress indicator (app/views/source_monitor/imports/* or similar).

Use these guidelines to implement the Health Check step backend jobs and Turbo Stream UI updates; leave view markup and job wiring details to the implementer following the repository's conventions.