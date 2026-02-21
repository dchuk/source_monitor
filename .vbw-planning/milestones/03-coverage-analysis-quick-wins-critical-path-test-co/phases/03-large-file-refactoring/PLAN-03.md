---
phase: 3
plan: 3
title: extract-import-sessions-controller
wave: 1
depends_on: []
skills_used: []
must_haves:
  truths:
    - "Running `wc -l app/controllers/source_monitor/import_sessions_controller.rb` shows fewer than 300 lines"
    - "Running `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0 with zero failures"
    - "Running `bin/rails test` exits 0 with no regressions (760+ runs, 0 failures)"
    - "Running `ls app/controllers/source_monitor/import_sessions/` shows at least 4 .rb files"
    - "Running `ruby -c app/controllers/source_monitor/import_sessions_controller.rb` exits 0"
    - "Running `grep -r 'ImportSessionsController' test/ --include='*.rb' -l` shows no test files were renamed or removed"
  artifacts:
    - "app/controllers/source_monitor/import_sessions/opml_parser.rb -- OPML file parsing and validation"
    - "app/controllers/source_monitor/import_sessions/entry_annotation.rb -- entry annotation, filtering, selection logic"
    - "app/controllers/source_monitor/import_sessions/health_check_management.rb -- health check lifecycle"
    - "app/controllers/source_monitor/import_sessions/bulk_configuration.rb -- bulk source configuration and settings"
    - "app/controllers/source_monitor/import_sessions_controller.rb -- slimmed to orchestrator under 300 lines"
  key_links:
    - "REQ-10 satisfied -- ImportSessionsController broken into focused concerns"
    - "Public API unchanged -- all wizard routes and step handling preserved"
---

# Plan 03: extract-import-sessions-controller

## Objective

Extract `app/controllers/source_monitor/import_sessions_controller.rb` (792 lines) into focused concerns under `app/controllers/source_monitor/import_sessions/`. The controller has five distinct responsibility clusters beyond the core CRUD: (1) OPML file parsing and validation, (2) entry annotation/filtering/selection, (3) health check lifecycle management, (4) bulk source configuration. Each becomes a concern module included in the controller. The controller retains the action methods (new, create, show, update, destroy), step handlers, and before_action filters.

## Context

<context>
@app/controllers/source_monitor/import_sessions_controller.rb -- 792 lines. The OPML import wizard controller. 5-step flow: upload -> preview -> health_check -> configure -> confirm. Contains file parsing, entry annotation, health check management, bulk configuration, selection management, and user authentication fallback.
@test/controllers/source_monitor/import_sessions_controller_test.rb -- 572 lines, integration tests for the wizard flow. MUST NOT be modified.
@app/controllers/concerns/source_monitor/sanitizes_search_params.rb -- existing controller concern pattern in this codebase
@lib/source_monitor/import_sessions/entry_normalizer.rb -- existing extracted support class for import sessions
@lib/source_monitor/sources/params.rb -- source parameter handling, used by the controller
@config/routes.rb -- routes for import_sessions (RESTful + step param)

**Decomposition rationale:** ImportSessionsController has four clearly separable responsibility clusters:
1. **OPML parsing** (parse_opml_file, build_entry, malformed_entry, outline_attribute, valid_feed_url?, validate_upload!, content_type_allowed?, generic_content_type?, build_file_metadata, uploading_file?, UploadError) -- ~100 lines, pure data transformation
2. **Entry annotation** (annotated_entries, normalize_entry, filter_entries, selectable_entries_from, selectable_entries, build_selection_from_params, health_check_selection_from_params, advancing_from_health_check?, advancing_from_preview?, normalize_page_param) -- ~100 lines, query/presentation logic
3. **Health check management** (start_health_checks_if_needed, reset_health_results, enqueue_health_check_jobs, deactivate_health_checks!, health_check_entries, health_check_progress, health_check_complete?, health_check_targets) -- ~100 lines, async job orchestration
4. **Bulk configuration** (build_bulk_source, build_bulk_source_from_session, build_bulk_source_from_params, sample_identity_attributes, selected_entries_for_identity, fallback_identity, configure_source_params, strip_identity_attributes, persist_bulk_settings_if_valid!, bulk_settings_payload, bulk_setting_keys) -- ~90 lines, source configuration logic

The remaining ~400 lines (action methods, step handlers, prepare_* context methods, user auth, step navigation) stay in the controller.

**Trade-offs considered:**
- Could use service objects instead of concerns. But these methods need controller context (params, render, redirect_to) or instance variables (@import_session, @current_step). Concerns are the idiomatic Rails pattern for extracting controller private methods.
- Could extract each wizard step into its own concern. But that fragments the step-handling logic too much and makes the flow harder to follow. Grouping by responsibility (parsing, annotation, health, config) is more cohesive.
- The user auth fallback methods (current_user_id, ensure_current_user!, fallback_user_id, create_guest_user, guest_value_for) are already inside a :nocov: block and are short (~60 lines). Leave them in the main controller -- they're security-sensitive and shouldn't be in a shared concern.

**What constrains the structure:**
- Concerns are placed in app/controllers/source_monitor/import_sessions/ (not in app/controllers/concerns/) because they're specific to this one controller. This follows the convention of co-locating private concerns with their controller.
- Each concern is `extend ActiveSupport::Concern` and `included in` the controller
- The controller must `include` the concerns and delegate appropriately
- All wizard step handling (handle_upload_step, handle_preview_step, etc.) stays in the main controller because they orchestrate across concerns
</context>

## Tasks

### Task 1: Extract OpmlParser concern

- **name:** extract-opml-parser
- **files:**
  - `app/controllers/source_monitor/import_sessions/opml_parser.rb` (new)
  - `app/controllers/source_monitor/import_sessions_controller.rb`
- **action:** Create `app/controllers/source_monitor/import_sessions/` directory. Create `opml_parser.rb` containing a `SourceMonitor::ImportSessions::OpmlParser` module using `extend ActiveSupport::Concern`. Move these methods into the concern as private methods:
  - `parse_opml_file` (lines 305-327)
  - `build_entry` (lines 329-353)
  - `malformed_entry` (lines 355-367)
  - `outline_attribute` (lines 369-372)
  - `valid_feed_url?` (lines 374-379)
  - `validate_upload!` (lines 282-295)
  - `content_type_allowed?` (lines 297-299)
  - `generic_content_type?` (lines 301-303)
  - `build_file_metadata` (lines 255-264)
  - `uploading_file?` (lines 266-268)

  Move the constants `ALLOWED_CONTENT_TYPES`, `GENERIC_CONTENT_TYPES`, and the `UploadError` class into the concern as well. In the controller, add `include SourceMonitor::ImportSessions::OpmlParser`. Remove the moved methods and constants from the controller. Add `require "source_monitor/import_sessions/opml_parser"` or rely on Rails autoloading in the app/ directory (prefer autoloading since this is in app/).
- **verify:** `ruby -c app/controllers/source_monitor/import_sessions/opml_parser.rb` exits 0 AND `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0
- **done:** OpmlParser concern extracted. Controller includes it. Tests pass.

### Task 2: Extract EntryAnnotation concern

- **name:** extract-entry-annotation
- **files:**
  - `app/controllers/source_monitor/import_sessions/entry_annotation.rb` (new)
  - `app/controllers/source_monitor/import_sessions_controller.rb`
- **action:** Create `entry_annotation.rb` containing a `SourceMonitor::ImportSessions::EntryAnnotation` module using `extend ActiveSupport::Concern`. Move these methods as private:
  - `annotated_entries` (lines 501-523)
  - `normalize_entry` (lines 561-564)
  - `filter_entries` (lines 566-575)
  - `selectable_entries_from` (lines 557-559)
  - `selectable_entries` (lines 607-609)
  - `build_selection_from_params` (lines 577-592)
  - `health_check_selection_from_params` (lines 594-605)
  - `advancing_from_health_check?` (lines 611-613)
  - `advancing_from_preview?` (lines 615-617)
  - `normalize_page_param` (lines 619-625)
  - `permitted_filter` (lines 778-783)
  - `preview_per_page` (lines 785-787)

  In the controller, add `include SourceMonitor::ImportSessions::EntryAnnotation`. Remove moved methods.
- **verify:** `ruby -c app/controllers/source_monitor/import_sessions/entry_annotation.rb` exits 0 AND `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0
- **done:** EntryAnnotation concern extracted. Tests pass.

### Task 3: Extract HealthCheckManagement concern

- **name:** extract-health-check-management
- **files:**
  - `app/controllers/source_monitor/import_sessions/health_check_management.rb` (new)
  - `app/controllers/source_monitor/import_sessions_controller.rb`
- **action:** Create `health_check_management.rb` containing a `SourceMonitor::ImportSessions::HealthCheckManagement` module. Move these methods as private:
  - `start_health_checks_if_needed` (lines 627-660)
  - `reset_health_results` (lines 753-761)
  - `enqueue_health_check_jobs` (lines 763-767)
  - `deactivate_health_checks!` (lines 769-776)
  - `health_check_entries` (lines 525-532)
  - `health_check_progress` (lines 534-545)
  - `health_check_complete?` (lines 547-549)
  - `health_check_targets` (lines 551-555)

  In the controller, add `include SourceMonitor::ImportSessions::HealthCheckManagement`. Remove moved methods.
- **verify:** `ruby -c app/controllers/source_monitor/import_sessions/health_check_management.rb` exits 0 AND `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0
- **done:** HealthCheckManagement concern extracted. Tests pass.

### Task 4: Extract BulkConfiguration concern

- **name:** extract-bulk-configuration
- **files:**
  - `app/controllers/source_monitor/import_sessions/bulk_configuration.rb` (new)
  - `app/controllers/source_monitor/import_sessions_controller.rb`
- **action:** Create `bulk_configuration.rb` containing a `SourceMonitor::ImportSessions::BulkConfiguration` module. Move these methods as private:
  - `build_bulk_source` (lines 675-682)
  - `build_bulk_source_from_session` (lines 662-665)
  - `build_bulk_source_from_params` (lines 667-673)
  - `sample_identity_attributes` (lines 684-694)
  - `selected_entries_for_identity` (lines 696-702)
  - `fallback_identity` (lines 704-709)
  - `configure_source_params` (lines 711-715)
  - `strip_identity_attributes` (lines 717-719)
  - `persist_bulk_settings_if_valid!` (lines 721-727)
  - `bulk_settings_payload` (lines 729-734)
  - `bulk_setting_keys` (lines 736-751)

  In the controller, add `include SourceMonitor::ImportSessions::BulkConfiguration`. Remove moved methods. After this task, verify the controller is under 300 lines. It should contain: before_actions, new, create, show, update, destroy, set_import_session, set_wizard_step, persist_step!, the 5 handle_*_step methods, the 4 prepare_*_context methods, state_params, permitted_step, target_step, session_attributes, auth methods, and the include statements. If the controller is between 300-320 lines, move `state_params`, `session_attributes`, `permitted_step`, and `target_step` into the EntryAnnotation concern (they're helper methods that support step navigation and parameter handling).
- **verify:** `ruby -c app/controllers/source_monitor/import_sessions/bulk_configuration.rb` exits 0 AND `wc -l app/controllers/source_monitor/import_sessions_controller.rb` shows fewer than 300 lines AND `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0 AND `bin/rails test` exits 0 with 760+ runs AND `bin/rubocop app/controllers/source_monitor/import_sessions_controller.rb app/controllers/source_monitor/import_sessions/` exits 0
- **done:** BulkConfiguration extracted. Controller under 300 lines. Full suite passes. RuboCop clean. REQ-10 satisfied.

## Verification

1. `wc -l app/controllers/source_monitor/import_sessions_controller.rb` shows fewer than 300 lines
2. `ls app/controllers/source_monitor/import_sessions/*.rb | wc -l` shows 4 files
3. `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0
4. `bin/rails test` exits 0 (no regressions)
5. `bin/rubocop app/controllers/source_monitor/import_sessions_controller.rb app/controllers/source_monitor/import_sessions/` exits 0

## Success Criteria

- [ ] ImportSessionsController main file under 300 lines (down from 792)
- [ ] Four concern modules created in app/controllers/source_monitor/import_sessions/
- [ ] No concern file exceeds 300 lines
- [ ] All wizard routes and step handling preserved
- [ ] All existing controller tests pass without modification (572 lines)
- [ ] Full test suite passes (760+ runs, 0 failures)
- [ ] RuboCop passes on all modified/new files
- [ ] REQ-10 satisfied
