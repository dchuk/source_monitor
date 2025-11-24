### Technical Summary

Implement a multi-step OPML import wizard accessible from the Sources index page, enabling admin users to upload an OPML file, preview and select sources, run health checks, configure bulk settings, and confirm import, with results stored for later viewing as import history.  
This extends SourceMonitor’s existing sources management, background job orchestration (Solid Queue), Turbo Streams real-time UI, and follows established Rails engine, controller, and asset pipeline patterns.

### System Design

#### **Frontend**
- Add "Import OPML" button to the Sources index page, linking to a dedicated wizard route.
- Wizard UI uses a sidebar for step navigation (Upload, Preview, Health Check, Configure, Confirm), with current step highlighted.
- Each step is rendered as a separate view, using Turbo Frames for partial updates and state transitions.
- File upload uses standard Rails form helpers, with immediate synchronous parsing and error feedback.
- Preview table paginates for large source lists, supports filters ("All", "New Sources", "Existing Sources"), and disables selection for duplicates/malformed entries.
- Selection state and bulk settings persist across steps using a temporary ImportSession record.
- Health check results update in real-time via Turbo Streams; unhealthy sources are unselected by default but can be re-selected.
- Bulk settings form reuses the single source creation partial, applying settings uniformly to all selected sources.
- Confirmation step displays a summary table of sources and settings; import progress and results are shown via Turbo Streams and static messaging.
- Accessibility, Tailwind styling, and Turbo conventions are followed throughout.

#### **Backend**
- Introduce an ImportSession model to persist wizard state (uploaded file, parsed sources, selections, settings) per user/session.
- OPML file is parsed synchronously in the controller; malformed entries are marked and excluded from selection.
- Duplicate detection matches only on feed URL, referencing existing sources in the database.
- Health checks for selected sources are enqueued as individual Solid Queue jobs; results are stored and broadcast via Turbo Streams.
- Import confirmation triggers a background job that creates sources individually, reporting errors per source and skipping duplicates.
- Import job results (successes, failures, skipped duplicates) are stored in an ImportHistory record for later viewing.
- Controllers follow SourceMonitor’s established RESTful and Turbo Stream response patterns, with strong parameter sanitization and error handling.
- If the user refreshes or exits the wizard, the ImportSession is discarded and progress is lost; navigation away triggers a JS warning.

#### **Data & Storage**
- Add `import_sessions` table to persist wizard state (user reference, OPML file metadata, parsed sources, selections, bulk settings, step state).
- Add `import_histories` table to store completed import results (timestamp, user, sources imported, failures, skipped duplicates, error details).
- No changes to existing `sourcemon_sources` table; duplicate detection uses feed URL matching.
- All new tables follow SourceMonitor’s naming, indexing, and migration conventions.

#### **Background Jobs**
- Health check jobs use existing Solid Queue infrastructure, leveraging SourceMonitor’s health check logic.
- Import job creates sources individually, logs errors per source, and updates ImportHistory.
- Job orchestration, retry, and error handling follow established patterns in app/jobs/source_monitor/*.

#### **Integrations**
- No new external integrations; leverages existing Feedjira (OPML parsing), Faraday (feed health checks), and Turbo Streams (real-time UI).
- All background jobs and real-time updates use Solid Queue and Solid Cable/Redis as configured.

#### **Security**
- Wizard and import actions restricted to authenticated admin users via SourceMonitor’s authentication hooks.
- All data access and mutations use strong parameter sanitization and follow engine security conventions.

#### **Testing**
- Unit, integration, and system tests cover wizard flow, OPML parsing, selection logic, health checks, bulk settings, import job, and import history.
- Use Minitest and VCR/WebMock for HTTP and feed parsing fixtures.
- Regression tests for edge cases: malformed OPML, all sources already imported, all health checks fail, large file uploads, concurrent imports.
- Turbo Stream and accessibility behaviors validated in system tests.

### Data Model / Schema Changes

| Table              | Column                | Type         | Description                                                        |
|--------------------|----------------------|--------------|--------------------------------------------------------------------|
| `import_sessions`  | `user_id`            | UUID (FK)    | References the admin user running the wizard                       |
|                    | `opml_file_metadata` | JSONB        | Stores OPML file info (filename, size, upload timestamp)           |
|                    | `parsed_sources`     | JSONB        | Array of parsed sources with status (valid, malformed, duplicate)  |
|                    | `selected_source_ids`| JSONB        | Array of selected source identifiers                               |
|                    | `bulk_settings`      | JSONB        | Bulk source settings to apply                                      |
|                    | `current_step`       | String       | Tracks wizard step for session                                     |
|                    | `created_at`         | Timestamp    | Creation time                                                      |
|                    | `updated_at`         | Timestamp    | Last update time                                                   |
| `import_histories` | `user_id`            | UUID (FK)    | References the admin user who performed the import                 |
|                    | `imported_sources`   | JSONB        | Array of successfully imported sources                             |
|                    | `failed_sources`     | JSONB        | Array of sources that failed to import with error details          |
|                    | `skipped_duplicates` | JSONB        | Array of sources skipped due to duplication                        |
|                    | `bulk_settings`      | JSONB        | Settings applied to imported sources                               |
|                    | `started_at`         | Timestamp    | Import start time                                                  |
|                    | `completed_at`       | Timestamp    | Import completion time                                             |

All new tables and columns follow SourceMonitor’s migration, indexing, and naming standards.