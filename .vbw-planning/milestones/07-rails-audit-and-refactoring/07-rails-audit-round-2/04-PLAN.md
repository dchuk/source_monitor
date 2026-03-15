---
phase: 7
plan: 04
title: View Layer & Accessibility
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-architecture, sm-engine-test, tdd-cycle]
files_modified:
  - app/components/source_monitor/status_badge_component.rb
  - app/components/source_monitor/status_badge_component.html.erb
  - app/views/source_monitor/sources/_row.html.erb
  - app/views/source_monitor/sources/_details.html.erb
  - app/views/source_monitor/dashboard/_recent_activity.html.erb
  - app/views/source_monitor/items/_details.html.erb
  - app/views/source_monitor/items/index.html.erb
  - app/views/source_monitor/logs/index.html.erb
  - app/views/source_monitor/sources/_bulk_scrape_modal.html.erb
  - app/views/source_monitor/sources/_bulk_scrape_enable_modal.html.erb
  - app/views/source_monitor/sources/new.html.erb
  - app/views/source_monitor/sources/edit.html.erb
  - app/views/source_monitor/shared/_form_errors.html.erb
  - app/views/source_monitor/shared/_pagination.html.erb
  - app/views/source_monitor/source_scrape_tests/show.html.erb
  - app/views/source_monitor/source_scrape_tests/_result.html.erb
  - app/assets/javascripts/source_monitor/controllers/modal_controller.js
  - app/helpers/source_monitor/application_helper.rb
  - test/components/source_monitor/status_badge_component_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "StatusBadgeComponent renders badge markup for all status types used in the engine"
    - "Modal templates have role='dialog' and aria-modal='true' attributes"
    - "Modal controller implements focus trapping (inert or tabindex management)"
    - "Inline database queries removed from view templates (_details.html.erb, _bulk_scrape_modal)"
  artifacts:
    - {path: "app/components/source_monitor/status_badge_component.rb", provides: "Reusable status badge", contains: "class StatusBadgeComponent"}
    - {path: "app/views/source_monitor/shared/_form_errors.html.erb", provides: "Shared form error partial", contains: "errors"}
    - {path: "app/views/source_monitor/shared/_pagination.html.erb", provides: "Shared pagination partial or validates existing one is used", contains: "pagination"}
  key_links:
    - {from: "app/components/source_monitor/status_badge_component.rb", to: "app/views/source_monitor/sources/_row.html.erb", via: "render StatusBadgeComponent.new(status:)"}
---
<objective>
Create StatusBadgeComponent to replace 12+ duplicated badge patterns (M20), add modal accessibility attributes and focus trapping (M22+M23), move inline database queries from views to controllers/presenters (M19), consolidate duplicated pagination and form error partials (L20, L23), and de-duplicate scrape test result markup (L21).
</objective>
<context>
@.claude/skills/sm-architecture/SKILL.md -- ViewComponent patterns, view layer structure
@.claude/skills/sm-engine-test/SKILL.md -- component test patterns
@.claude/skills/tdd-cycle/SKILL.md -- TDD workflow

Key context: Status badge markup (inline-flex items-center rounded-full with conditional colors/spinners) is duplicated 12+ times across sources, items, dashboard, and logs views. The engine already has IconComponent as a ViewComponent pattern to follow. Modals are plain divs without WCAG dialog attributes. Items _details.html.erb and _bulk_scrape_modal.html.erb execute database queries directly. Items and Logs index pages duplicate pagination markup instead of using the shared _pagination partial.
</context>
<tasks>
<task type="auto">
  <name>Create StatusBadgeComponent (M20)</name>
  <files>
    app/components/source_monitor/status_badge_component.rb
    app/components/source_monitor/status_badge_component.html.erb
    test/components/source_monitor/status_badge_component_test.rb
  </files>
  <action>
1. Create StatusBadgeComponent following the existing IconComponent pattern. Accept `status` (string/symbol) and optional `size` parameter.
2. Map statuses to colors: working/active/success -> green, failing/failed/error -> red, declining/warning -> yellow, idle/pending/queued -> gray, fetching/processing -> blue with spinner.
3. Handle the spinner case (fetching/processing statuses show an animated spinner icon).
4. Create the ERB template with the badge markup currently duplicated across views.
5. Write component tests covering: each status variant renders correct color classes, spinner shows for processing statuses, unknown status falls back to gray.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/components/source_monitor/status_badge_component_test.rb
  </verify>
  <done>
StatusBadgeComponent exists with tests. Renders correct badge markup for all status types.
  </done>
</task>
<task type="auto">
  <name>Replace inline badge markup with StatusBadgeComponent</name>
  <files>
    app/views/source_monitor/sources/_row.html.erb
    app/views/source_monitor/sources/_details.html.erb
    app/views/source_monitor/dashboard/_recent_activity.html.erb
    app/views/source_monitor/items/_details.html.erb
    app/views/source_monitor/items/index.html.erb
    app/views/source_monitor/logs/index.html.erb
    app/helpers/source_monitor/application_helper.rb
  </files>
  <action>
1. In each view template, find the hand-crafted status badge `<span class="inline-flex items-center rounded-full ...">` patterns and replace with `render StatusBadgeComponent.new(status: ...)`.
2. If ApplicationHelper has badge-related helper methods, update them to use StatusBadgeComponent or mark them as deprecated.
3. Run the existing view/controller tests to ensure rendering still works.

Note: Be careful to preserve the exact status value being displayed. Some views may use fetch_status, health_status, scrape_status, or custom status strings. The component should accept all of these.
  </action>
  <verify>
bin/rails test test/controllers/ test/system/ -- existing view tests still pass
  </verify>
  <done>
All inline badge markup replaced with StatusBadgeComponent. No hand-crafted badge spans remain in view templates.
  </done>
</task>
<task type="auto">
  <name>Add modal accessibility and focus trapping (M22+M23)</name>
  <files>
    app/views/source_monitor/sources/_bulk_scrape_modal.html.erb
    app/views/source_monitor/sources/_bulk_scrape_enable_modal.html.erb
    app/assets/javascripts/source_monitor/controllers/modal_controller.js
  </files>
  <action>
1. M22: Add `role="dialog"`, `aria-modal="true"`, and `aria-labelledby` (pointing to the modal heading's ID) to both modal template root elements.
2. M23: In modal_controller.js, implement focus trapping:
   - On open: set `inert` attribute on sibling elements of the modal (elements behind the backdrop).
   - On close: remove `inert` from those elements.
   - Alternative: if `inert` is not well-supported, use a tabindex-based approach that captures Tab and Shift+Tab at the modal boundaries.
3. Ensure Escape key still closes the modal (already implemented per research).
  </action>
  <verify>
yarn build -- JS builds without errors
  </verify>
  <done>
Modal templates have role="dialog", aria-modal="true", aria-labelledby. Modal controller traps focus within dialog.
  </done>
</task>
<task type="auto">
  <name>Move inline queries from views + consolidate partials (M19, L20, L21, L23)</name>
  <files>
    app/views/source_monitor/items/_details.html.erb
    app/views/source_monitor/sources/_bulk_scrape_modal.html.erb
    app/views/source_monitor/items/index.html.erb
    app/views/source_monitor/logs/index.html.erb
    app/views/source_monitor/shared/_pagination.html.erb
    app/views/source_monitor/shared/_form_errors.html.erb
    app/views/source_monitor/sources/new.html.erb
    app/views/source_monitor/sources/edit.html.erb
    app/views/source_monitor/source_scrape_tests/show.html.erb
    app/views/source_monitor/source_scrape_tests/_result.html.erb
  </files>
  <action>
1. M19: In items/_details.html.erb, replace `item.scrape_logs.order(...).limit(5)` with a local variable passed from the controller. Update the controller action to pass `recent_scrape_logs` as a local. Similarly fix any inline queries in _bulk_scrape_modal.html.erb by moving queries to the controller.
2. L20: If a shared _pagination.html.erb partial exists, update items/index.html.erb and logs/index.html.erb to use it instead of duplicating pagination markup. If no shared partial exists, create one based on the sources pagination pattern and use it in all three index pages.
3. L21: De-duplicate scrape test result markup between show.html.erb and _result.html.erb. Have the show page render the _result partial.
4. L23: Create shared/_form_errors.html.erb for validation error display. Use it in sources/new.html.erb and edit.html.erb to replace duplicated error blocks.
  </action>
  <verify>
bin/rails test test/controllers/ -- controller tests pass with moved query logic
  </verify>
  <done>
No database queries in view templates. Pagination uses shared partial. Scrape test result de-duplicated. Form errors use shared partial.
  </done>
</task>
<task type="auto">
  <name>Fix FilterDropdownComponent and Logs Turbo Frame (L27, M24)</name>
  <files>
    app/views/source_monitor/logs/index.html.erb
    app/helpers/source_monitor/application_helper.rb
  </files>
  <action>
1. L27: In the FilterDropdownComponent (or the helper that generates the dropdown), replace inline `onchange` JavaScript with a Stimulus action (e.g., `data-action="change->filter#submit"`). Use the existing filter Stimulus controller if one exists, or create a minimal one.
2. M24: Wrap the logs index table and pagination in a `turbo_frame_tag "logs"`. Update the `form_with` to remove `local: true` so Turbo handles the form submission. This matches the pattern used by Sources and Items index pages.

Note: Check if FilterDropdownComponent is a ViewComponent or a helper method. If it's a ViewComponent, modify the component file (which is in Plan 04's file set). If it generates HTML via a helper, modify application_helper.rb.
  </action>
  <verify>
bin/rails test test/controllers/source_monitor/logs_controller_test.rb
  </verify>
  <done>
FilterDropdown uses Stimulus action instead of inline onchange. Logs index has Turbo Frame for filter/pagination.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes
2. bin/rubocop app/components/ app/views/ app/helpers/ -- zero offenses
3. yarn build -- JS builds without errors
4. grep -r "inline-flex items-center rounded-full" app/views/ returns no matches (all badges use component)
5. grep "role=\"dialog\"" app/views/source_monitor/sources/_bulk_scrape_modal.html.erb returns a match
6. grep -r "\.order\|\.limit\|\.where" app/views/source_monitor/items/_details.html.erb returns no matches (no inline queries)
</verification>
<success_criteria>
- StatusBadgeComponent replaces 12+ duplicated badge patterns with tests (M20)
- Modals have role="dialog", aria-modal="true", aria-labelledby, and focus trapping (M22+M23)
- No database queries in view templates (M19)
- Shared pagination partial used across all index pages (L20)
- Scrape test result de-duplicated (L21)
- Form errors use shared partial (L23)
- FilterDropdown uses Stimulus, Logs index has Turbo Frame (L27, M24)
- All tests pass with zero regressions
</success_criteria>
<output>
04-SUMMARY.md
</output>
