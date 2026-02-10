---
phase: 4
plan: 1
title: conventions-audit
wave: 1
depends_on: []
skills_used: []
cross_phase_deps:
  - "Phase 3 completed -- FeedFetcher, Configuration, ImportSessionsController already refactored"
must_haves:
  truths:
    - "Running `bin/rubocop -f simple` shows `no offenses detected`"
    - "Running `bin/rails test` exits 0 with 760+ runs and 0 failures"
    - "Running `grep -n 'def fetch' app/controllers/source_monitor/sources_controller.rb` returns no matches"
    - "Running `grep -n 'def retry' app/controllers/source_monitor/sources_controller.rb` returns no matches"
    - "The file `test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb` does not exist (duplicate removed)"
    - "The `new` action in `app/controllers/source_monitor/import_sessions_controller.rb` delegates to `create` (one-liner, no duplicated body)"
  artifacts:
    - "db/migrate/20260210204022_add_composite_index_to_log_entries.rb -- RuboCop violations fixed"
    - "app/controllers/source_monitor/sources_controller.rb -- dead fetch/retry methods removed"
    - "app/controllers/source_monitor/import_sessions_controller.rb -- duplicated new action removed"
  key_links:
    - "REQ-15 partially satisfied -- controllers follow CRUD-only conventions"
    - "Phase 4 success criterion #2 -- zero RuboCop violations"
---

# Plan 01: conventions-audit

## Objective

Audit and fix all convention violations across the codebase: remove dead code from controllers, eliminate duplicated methods, fix existing RuboCop violations, and clean up duplicate test files. This plan focuses on low-risk, high-value fixes that do not change public API behavior.

## Context

<context>
@app/controllers/source_monitor/sources_controller.rb -- 148 lines. Contains dead `fetch` (line 113) and `retry` (line 120) methods. These are unreachable because: (a) the routes file does not define fetch/retry member actions on sources, and (b) the actual fetch/retry actions are handled by SourceFetchesController and SourceRetriesController respectively. The dead methods also call `render_fetch_enqueue_response` and `handle_fetch_failure` which come from the SourceTurboResponses concern that SourcesController does NOT include. These methods would raise NoMethodError if somehow invoked.

@app/controllers/source_monitor/import_sessions_controller.rb -- 295 lines. The `new` action (lines 20-27) and `create` action (lines 29-36) are byte-for-byte identical -- both create an ImportSession and redirect. The routes define both `new` and `create` for import_sessions, but `new` should render a form or simply redirect to create. Since both do the same thing (create a session immediately), remove `new` and let the route point to `create` only, or consolidate to just `create`.

@db/migrate/20260210204022_add_composite_index_to_log_entries.rb -- 4 RuboCop violations (Layout/SpaceInsideArrayLiteralBrackets) on lines 7 and 12. Two are autocorrectable.

@test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb -- Duplicate test file. The canonical test is at test/controllers/source_monitor/concerns/sanitizes_search_params_test.rb. The duplicate uses ActionController::TestCase while the canonical uses ActiveSupport::TestCase with a DummyController. Both test the same concern.

@config/routes.rb -- 26 lines. Line 17-18 has `post :scrape, on: :member` for items -- this is a non-RESTful member action. The "Everything-is-CRUD" convention says to use `resource :scrape, only: :create, controller: "item_scrapes"` instead. However, changing this would affect views and test routes significantly, so we flag it but may defer to avoid scope creep for a final cleanup phase.

@app/controllers/source_monitor/source_fetches_controller.rb -- Already follows CRUD pattern (create-only resource controller).
@app/controllers/source_monitor/source_retries_controller.rb -- Already follows CRUD pattern.
@app/controllers/source_monitor/source_turbo_responses.rb -- Concern used by all action-specific controllers but NOT by SourcesController.

**Rationale:** The dead code in SourcesController is a leftover from before the CRUD extraction in Phase 3. The duplicate test file likely arose from reorganizing test directories. The RuboCop violations were introduced by Phase 3's migration. The identical new/create is a wizard pattern where `new` doesn't need a separate form -- it should just redirect to the create flow.
</context>

## Tasks

### Task 1: Fix RuboCop violations in migration file

- **name:** fix-rubocop-migration
- **files:**
  - `db/migrate/20260210204022_add_composite_index_to_log_entries.rb`
- **action:** Fix all 4 `Layout/SpaceInsideArrayLiteralBrackets` violations. Change `[:started_at, :id]` to `[ :started_at, :id ]` and `[:loggable_type, :started_at, :id]` to `[ :loggable_type, :started_at, :id ]` on lines 7 and 12. Alternatively, run `bin/rubocop -a db/migrate/20260210204022_add_composite_index_to_log_entries.rb` to autocorrect.
- **verify:** `bin/rubocop db/migrate/20260210204022_add_composite_index_to_log_entries.rb` exits 0 with no offenses AND `bin/rubocop -f simple` shows `no offenses detected` across entire codebase
- **done:** Zero RuboCop violations in the entire codebase.

### Task 2: Remove dead fetch/retry methods from SourcesController

- **name:** remove-dead-controller-methods
- **files:**
  - `app/controllers/source_monitor/sources_controller.rb`
- **action:** Delete the `fetch` method (lines 113-118) and the `retry` method (lines 120-125) from SourcesController. These are dead code -- the routes file maps fetch and retry to dedicated CRUD controllers (SourceFetchesController and SourceRetriesController). Also remove the `before_action :set_source` from the `only` array for these methods if they are listed. Verify that no routes reference `sources#fetch` or `sources#retry`. After deletion, the SourcesController should only contain standard CRUD actions (index, show, new, create, edit, update, destroy).
- **verify:** `bin/rails test test/controllers/source_monitor/sources_controller_test.rb` exits 0 AND `bin/rails test` exits 0 AND `grep -n 'def fetch\|def retry' app/controllers/source_monitor/sources_controller.rb` returns no matches
- **done:** Dead fetch/retry methods removed. All tests pass. SourcesController is CRUD-only.

### Task 3: Remove duplicated `new` action from ImportSessionsController

- **name:** remove-duplicate-new-action
- **files:**
  - `app/controllers/source_monitor/import_sessions_controller.rb`
  - `config/routes.rb`
- **action:** The `new` and `create` actions are identical. Remove the `new` method entirely from the controller. In `config/routes.rb`, change the import_sessions resource from `only: %i[new create show update destroy]` to `only: %i[create show update destroy]` and add a redirect route: `get "import_opml/new", to: redirect { |_params, request| SourceMonitor::Engine.routes.url_helpers.import_sessions_path }, as: :new_import_session`. Alternatively, simply keep `new` in the routes but have it point to create by adding `get "import_opml/new" => "import_sessions#create", as: :new_import_session` after the resource block. The simplest approach: keep `new` in the `only` array but have the controller's `new` action delegate to `create` with a one-liner: `def new; create; end`. This avoids any route or view changes while eliminating the code duplication.
- **verify:** `bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb` exits 0 AND `bin/rails test` exits 0
- **done:** No duplicated code between new and create. All tests pass.

### Task 4: Remove duplicate test file

- **name:** remove-duplicate-test
- **files:**
  - `test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb` (delete)
- **action:** Delete the duplicate test file at `test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb`. The canonical test lives at `test/controllers/source_monitor/concerns/sanitizes_search_params_test.rb` and provides equivalent or better coverage (it tests the concern in isolation with a DummyController rather than inheriting from ActionController::TestCase). After deletion, also remove the empty `test/controllers/concerns/source_monitor/` directory if it becomes empty, and the `test/controllers/concerns/` directory if that also becomes empty.
- **verify:** `bin/rails test test/controllers/source_monitor/concerns/sanitizes_search_params_test.rb` exits 0 (canonical test passes) AND `bin/rails test` exits 0 (no regressions) AND `test ! -f test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb` (duplicate gone)
- **done:** Single canonical test file. No duplicate test directories. Full suite passes.

### Task 5: Audit and fix remaining controller conventions

- **name:** audit-controller-conventions
- **files:**
  - `app/controllers/source_monitor/sources_controller.rb`
  - `app/controllers/source_monitor/items_controller.rb`
  - Any other controllers with convention issues found during audit
- **action:** Do a final pass across all controllers checking for: (a) consistent `before_action` usage with `only:` constraints, (b) no private constants defined in the wrong scope (SourcesController has `SEARCH_FIELD` after `before_action` which is fine but should be at the top with other constants), (c) verify all controllers inherit from ApplicationController, (d) ensure all strong parameter methods use `params.require().permit()` or the existing `Sources::Params.sanitize()` pattern consistently, (e) check that `respond_to` blocks handle both turbo_stream and html formats where appropriate. Fix any issues found. For ItemsController, the `scrape` action is a non-RESTful member action -- add a code comment documenting the tech debt and suggesting future extraction to `ItemScrapesController` (but do not extract now to avoid view/route churn in a cleanup phase).
- **verify:** `bin/rubocop app/controllers/` exits 0 AND `bin/rails test` exits 0
- **done:** All controllers follow conventions. Any tech debt is documented with comments.

## Verification

1. `bin/rubocop -f simple` shows `no offenses detected`
2. `bin/rails test` exits 0 with 760+ runs and 0 failures
3. `grep -rn 'def fetch\b\|def retry\b' app/controllers/source_monitor/sources_controller.rb` returns no matches
4. `test ! -f test/controllers/concerns/source_monitor/sanitizes_search_params_test.rb` returns true
5. All controller files pass RuboCop

## Success Criteria

- [ ] Zero RuboCop violations across entire codebase
- [ ] Dead fetch/retry methods removed from SourcesController
- [ ] Duplicate new/create code eliminated in ImportSessionsController
- [ ] Duplicate test file removed
- [ ] All 760+ tests pass with 0 failures
- [ ] Controllers follow CRUD-only conventions (tech debt documented where not yet extracted)
- [ ] REQ-15 partially satisfied (controllers audited and cleaned)
