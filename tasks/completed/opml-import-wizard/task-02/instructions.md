**Context**

- This task implements the "Upload" step of the OPML import wizard for the SourceMonitor engine.
- The wizard shell and ImportSession persistence are provided by the wizard shell task; this task must wire the upload form and synchronous parsing into that flow.
- Parsing should use the repo's existing feed parsing libraries (Feedjira/Nokogiri patterns) and persist parsed results into ImportSession.parsed_sources (JSONB). Malformed entries must be flagged and excluded from selection in the Preview step.

**Goals**

- Add an upload form for the Upload step that accepts an OPML file and validates file type before parsing.
- Parse the uploaded OPML file synchronously in the controller action handling the Upload step.
- Extract feed entries and persist them into ImportSession.parsed_sources as JSONB.
- Mark malformed/unparsable entries with a status and an error message so they are not selectable in Preview.
- Prevent navigation to Preview until ImportSession.parsed_sources contains at least one valid parsed entry; surface actionable error messages for invalid file / parse failures.
- Follow SourceMonitor engine conventions (strong params, user scoping, security, Tailwind/Turbo forms).

**Technical Guidelines**

- Controller & route
  - Implement a POST action on the wizard Upload step controller (the wizard route provided by the shell) that receives the uploaded file and the ImportSession identifier (or creates/loads ImportSession for current admin).
  - Enforce admin-only access via existing SourceMonitor authentication hooks.
  - Use strong parameter sanitization for the file param and ImportSession id.

- File handling & validation
  - Accept standard Rails file upload types (ActionDispatch::Http::UploadedFile). Validate the upload exists and is non-empty.
  - Perform a content-type check for XML/OPML (e.g., application/xml, text/xml, text/x-opml, application/opml) but do not rely solely on content-type: if content-type is absent or generic, attempt XML parsing anyway.
  - Read the uploaded file via tempfile or uploaded_file.read in a memory-conscious way. Follow engine file handling safety conventions (tempfiles, no persistent file writes unless required by ImportSession metadata).
  - Persist basic OPML file metadata into ImportSession.opml_file_metadata (filename, size, uploaded_at).

- Synchronous parsing
  - Parse synchronously in the controller request handling the Upload step—do not enqueue parsing to background jobs.
  - Reuse existing parsing patterns: prefer Feedjira for feed handling when applicable and Nokogiri for XML traversal (OPML is XML). Use Feedjira/Nokogiri idioms already present in the repo (inspect lib/source_monitor/fetching/feed_fetcher.rb and feedjira init).
  - Traverse OPML outlines to extract feed entries; for each candidate entry, normalize and extract at minimum: feed URL (required), title (if present), website/HTML URL (if present), and any obvious metadata.
  - For entries that cannot be parsed (malformed XML snippet, missing feed URL, invalid URL), produce an entry object with a status (e.g., "malformed") and an error message describing the issue.
  - For successfully parsed entries produce an entry object with status "valid" and extracted fields. Do not perform duplicate detection here (preview task handles duplicates), but include the feed_url so preview can detect duplicates by comparing against existing sourcemon_sources.

- Persisting parsed results
  - Store the array of parsed entry objects into ImportSession.parsed_sources (JSONB). Also update ImportSession.opml_file_metadata and ImportSession.current_step if appropriate.
  - Parsed entries must include:
    - stable temporary id or index (so UI can refer to rows)
    - feed_url (string)
    - title (string|null)
    - website_url (string|null)
    - status: "valid" | "malformed"
    - error: string (present when status == "malformed")
    - any other minimal metadata useful to Preview (e.g., raw_outline_index, line/position optional)
  - Ensure ImportSession is scoped to the current user (user_id integer) and use standard ActiveRecord integer primary key conventions (do not change user id type).

- Errors & UX constraints
  - If the uploaded file is not valid XML / OPML, return an actionable error message on the Upload view (do not crash). Do not advance to Preview.
  - If parsing succeeds but yields zero valid entries, block progression to Preview and show a clear message instructing the user to upload a different OPML or correct the file.
  - If parsing yields some valid entries, persist them and redirect/render the Preview step UI via Turbo Frames (the wizard shell controls the step rendering). Ensure selections are not created yet—only parsed_sources persisted.

- Security & limits
  - Respect standard engine security: only admin users can upload; operate on ImportSession scoped to current user.
  - Use tempfile APIs provided by Rails for file reading; do not dangerously evaluate XML. Use safe Nokogiri parsing options (no external entity expansion).
  - Do not implement custom file size limits in this task (out of scope), but parse in a way that does not load huge files into excessive memory when possible.

- Testing guidance (what to cover)
  - Controller tests for successful upload and parsing storing parsed_sources with both valid and malformed entries.
  - Tests for invalid file types and malformed XML returning appropriate errors and not advancing to Preview.
  - Verify ImportSession is updated (opml_file_metadata and parsed_sources) and is scoped to current user.
  - Use existing repo test helpers and VCR/webmock patterns if parsing makes external requests (should not for pure OPML parsing).

**Out of scope**

- Preview UI/table rendering, filters or pagination (Preview task handles these).
- Duplicate detection or marking duplicates as part of parsing (Preview task handles matching feed_url against existing sourcemon_sources).
- Backgrounding parsing or streaming large-file parsing—parsing must be synchronous per requirements.
- Per-feed settings, health checks, or import confirmation logic.
- File storage beyond keeping metadata in ImportSession.opml_file_metadata.

**Suggested research (inspect before implementing)**

- Existing feed parsing patterns:
  - lib/source_monitor/fetching/feed_fetcher.rb (Feedjira usage and parsing patterns)
  - config/initializers/feedjira.rb (any repo customizations)
- Wizard shell controller/layout and ImportSession model/location created by the wizard shell task:
  - Routes and controller names for the wizard Upload step (app/controllers/... likely under source_monitor/import_sessions or import_wizard controller).
  - ImportSession model/migration shape (fields: parsed_sources JSONB, opml_file_metadata JSONB, user_id integer).
- Existing examples of file upload handling and strong param patterns across the engine (SourcesController create/update forms and controllers under app/controllers/source_monitor).
- Nokogiri safe parsing patterns used in repo (search for Nokogiri usage) to avoid unsafe XML parsing options.

Implement only the Upload step controller action, the upload form view for the Upload step, synchronous parsing and persistence to ImportSession.parsed_sources, and the error/flow control that blocks Preview until at least one valid parsed entry exists.