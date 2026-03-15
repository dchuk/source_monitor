---
phase: 7
plan: 02
title: Controller DRY & Robustness
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-architecture, sm-engine-test, rails-architecture, tdd-cycle]
files_modified:
  - app/controllers/source_monitor/application_controller.rb
  - app/controllers/concerns/source_monitor/set_source.rb
  - app/controllers/source_monitor/source_fetches_controller.rb
  - app/controllers/source_monitor/source_retries_controller.rb
  - app/controllers/source_monitor/source_bulk_scrapes_controller.rb
  - app/controllers/source_monitor/source_health_checks_controller.rb
  - app/controllers/source_monitor/source_health_resets_controller.rb
  - app/controllers/source_monitor/source_favicon_fetches_controller.rb
  - app/controllers/source_monitor/source_scrape_tests_controller.rb
  - app/controllers/source_monitor/bulk_scrape_enablements_controller.rb
  - app/controllers/source_monitor/import_sessions_controller.rb
  - app/controllers/concerns/source_monitor/sanitizes_search_params.rb
  - test/controllers/source_monitor/application_controller_test.rb
  - test/controllers/source_monitor/source_fetches_controller_test.rb
  - test/controllers/source_monitor/bulk_scrape_enablements_controller_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "set_source is defined once in a SetSource concern, not in individual controllers"
    - "ApplicationController has rescue_from ActiveRecord::RecordNotFound returning 404"
    - "fallback_user_id is guarded by Rails.env.development? or similar safety check"
    - "BulkScrapeEnablementsController uses Source.enable_scraping! class method"
  artifacts:
    - {path: "app/controllers/concerns/source_monitor/set_source.rb", provides: "Shared set_source concern", contains: "module SetSource"}
    - {path: "app/controllers/source_monitor/application_controller.rb", provides: "rescue_from RecordNotFound", contains: "rescue_from ActiveRecord::RecordNotFound"}
  key_links:
    - {from: "app/controllers/concerns/source_monitor/set_source.rb", to: "app/controllers/source_monitor/source_fetches_controller.rb", via: "include SetSource"}
---
<objective>
Extract shared controller patterns: SetSource concern for 7 controllers (M6), rescue_from RecordNotFound in ApplicationController (M5), guard fallback_user_id (M7), extract BulkScrapeEnablements business logic to model (M10), and fix minor controller issues (L1, L2, L4, L7).
</objective>
<context>
@.claude/skills/sm-architecture/SKILL.md -- engine architecture, controller patterns
@.claude/skills/sm-engine-test/SKILL.md -- controller integration test patterns
@.claude/skills/rails-architecture/SKILL.md -- CRUD conventions, concern patterns
@.claude/skills/tdd-cycle/SKILL.md -- TDD workflow

Key context: 7 controllers each define identical `def set_source; @source = Source.find(params[:source_id]); end`. ApplicationController has no rescue_from handlers. ImportSessionsController creates guest users in host-app tables. BulkScrapeEnablementsController has update_all logic inline.
</context>
<tasks>
<task type="auto">
  <name>Extract SetSource concern (M6)</name>
  <files>
    app/controllers/concerns/source_monitor/set_source.rb
    app/controllers/source_monitor/source_fetches_controller.rb
    app/controllers/source_monitor/source_retries_controller.rb
    app/controllers/source_monitor/source_bulk_scrapes_controller.rb
    app/controllers/source_monitor/source_health_checks_controller.rb
    app/controllers/source_monitor/source_health_resets_controller.rb
    app/controllers/source_monitor/source_favicon_fetches_controller.rb
    app/controllers/source_monitor/source_scrape_tests_controller.rb
  </files>
  <action>
1. Create `app/controllers/concerns/source_monitor/set_source.rb` with:
```ruby
module SourceMonitor
  module SetSource
    extend ActiveSupport::Concern

    private

    def set_source
      @source = Source.find(params[:source_id])
    end
  end
end
```
2. In each of the 7 controllers, replace the local `set_source` method with `include SourceMonitor::SetSource`.
3. Keep the `before_action :set_source` declarations in each controller (they reference the method by name).
  </action>
  <verify>
bin/rails test test/controllers/
  </verify>
  <done>
SetSource concern exists. All 7 controllers include it. grep -r "def set_source" app/controllers/ returns only the concern file.
  </done>
</task>
<task type="auto">
  <name>Add rescue_from RecordNotFound (M5)</name>
  <files>
    app/controllers/source_monitor/application_controller.rb
    test/controllers/source_monitor/application_controller_test.rb
  </files>
  <action>
1. In ApplicationController, add:
```ruby
rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

private

def record_not_found
  respond_to do |format|
    format.html { render plain: "Record not found", status: :not_found }
    format.turbo_stream {
      render turbo_stream: turbo_stream.append("flash", partial: "source_monitor/shared/toast",
        locals: { message: "Record not found", level: :error }), status: :not_found
    }
    format.json { render json: { error: "Record not found" }, status: :not_found }
  end
end
```
Note: Check if the engine has a toast partial or uses a different flash pattern. Adapt the turbo_stream response to match existing patterns.

2. Write a test that hits a controller action with a non-existent ID and asserts 404 response.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/controllers/source_monitor/application_controller_test.rb
  </verify>
  <done>
ApplicationController has rescue_from RecordNotFound. Test proves 404 response for missing records.
  </done>
</task>
<task type="auto">
  <name>Guard fallback_user_id and fix ImportSessions issues (M7, L1)</name>
  <files>
    app/controllers/source_monitor/import_sessions_controller.rb
  </files>
  <action>
1. M7: Wrap the `fallback_user_id` method's user-creation logic in a `Rails.env.development? || Rails.env.test?` guard. In production, return nil or raise a descriptive error instead of creating host-app records.
2. L1: The `new` action delegates to `create` which means a GET request creates a record. If this is the current behavior, add a comment explaining why (wizard pattern that needs a session record), or refactor so `new` renders a form and `create` handles the POST. Follow existing engine patterns.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/controllers/source_monitor/import_sessions_controller_test.rb
  </verify>
  <done>
fallback_user_id guarded behind development/test environment check. L1 addressed with comment or refactor.
  </done>
</task>
<task type="auto">
  <name>Extract BulkScrapeEnablements logic + minor controller fixes (M10, L2, L4)</name>
  <files>
    app/controllers/source_monitor/bulk_scrape_enablements_controller.rb
    app/controllers/source_monitor/source_health_checks_controller.rb
    test/controllers/source_monitor/bulk_scrape_enablements_controller_test.rb
  </files>
  <action>
1. M10: Move the update_all logic from BulkScrapeEnablementsController into a Source class method: `Source.enable_scraping!(ids)`. Controller calls the class method.
2. L2: Wrap params access in BulkScrapeEnablementsController with a strong params method.
3. L4: In SourceHealthChecksController, move inline Tailwind class strings to view helpers or a constant. The controller should not contain presentation markup.
4. Add/update tests for the refactored controller.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/controllers/source_monitor/bulk_scrape_enablements_controller_test.rb test/controllers/source_monitor/source_health_checks_controller_test.rb
  </verify>
  <done>
Source.enable_scraping! class method exists. BulkScrapeEnablementsController uses strong params. SourceHealthChecksController has no inline Tailwind.
  </done>
</task>
<task type="auto">
  <name>Document to_unsafe_h usage (L7)</name>
  <files>
    app/controllers/concerns/source_monitor/sanitizes_search_params.rb
  </files>
  <action>
1. L7: Add a comment above the `to_unsafe_h` call explaining why it's used (Ransack requires a plain hash, and the params have already been sanitized by the concern's allowlist at this point). This documents the intentional bypass of strong params for the Ransack query builder.
  </action>
  <verify>
grep -n "to_unsafe_h" app/controllers/concerns/source_monitor/sanitizes_search_params.rb shows the comment above the call
  </verify>
  <done>
to_unsafe_h usage is documented with rationale comment.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test test/controllers/ -- all controller tests pass
2. bin/rubocop app/controllers/ -- zero offenses
3. grep -r "def set_source" app/controllers/ returns only app/controllers/concerns/source_monitor/set_source.rb
4. grep "rescue_from" app/controllers/source_monitor/application_controller.rb returns RecordNotFound handler
5. grep "fallback_user_id" app/controllers/ shows development/test guard
</verification>
<success_criteria>
- SetSource concern extracted, included in 7 controllers (M6)
- rescue_from RecordNotFound added to ApplicationController with 404 response (M5)
- fallback_user_id guarded to non-production environments (M7)
- Source.enable_scraping! class method replaces inline controller logic (M10)
- Strong params in BulkScrapeEnablementsController (L2)
- No Tailwind classes in SourceHealthChecksController (L4)
- to_unsafe_h documented (L7)
- All controller tests pass
</success_criteria>
<output>
02-SUMMARY.md
</output>
