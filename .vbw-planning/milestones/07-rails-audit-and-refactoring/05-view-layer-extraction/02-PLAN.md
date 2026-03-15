---
phase: "05"
plan: "02"
title: "FilterDropdownComponent & SourcesIndexPresenter"
wave: 1
depends_on: []
skills_used:
  - viewcomponent-patterns
  - rails-presenter
  - tdd-cycle
  - hotwire-patterns
  - sm-architecture
must_haves:
  - "New SourceMonitor::FilterDropdownComponent at app/components/source_monitor/filter_dropdown_component.rb with label, param_name, options, selected_value params"
  - "FilterDropdownComponent renders a labeled select with auto-submit on change and consistent Tailwind styling"
  - "FilterDropdownComponent test at test/components/source_monitor/filter_dropdown_component_test.rb covers rendering, selected state, and auto-submit attribute"
  - "New SourceMonitor::SourcesFilterPresenter at app/presenters/source_monitor/sources_filter_presenter.rb with active_filter_keys, filter_labels, has_any_filter?, adapter_options methods"
  - "SourcesFilterPresenter test at test/presenters/source_monitor/sources_filter_presenter_test.rb covers filter label generation and active filter detection"
  - "sources/index.html.erb uses FilterDropdownComponent for all filter selects and SourcesFilterPresenter for filter state logic"
  - "items/index.html.erb and logs/index.html.erb use FilterDropdownComponent for their filter selects"
  - "Turbo Frame IDs in sources/index, items/index follow source_monitor_{section}_{element} convention"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 02: FilterDropdownComponent & SourcesIndexPresenter

## Objective

Extract duplicated filter dropdown markup from 3 index views into a shared `FilterDropdownComponent` (V5), extract filter state logic from `sources/index.html.erb` into a `SourcesFilterPresenter` (V1), document row preload requirements (V3), and standardize Turbo Frame naming (V12).

## Context

- @.claude/skills/viewcomponent-patterns/SKILL.md -- ViewComponent patterns with TDD
- @.claude/skills/rails-presenter/SKILL.md -- Presenter extraction with BasePresenter
- @.claude/skills/tdd-cycle/SKILL.md -- TDD red-green-refactor workflow
- @.claude/skills/hotwire-patterns/SKILL.md -- Turbo Frame naming and patterns
- @.claude/skills/sm-architecture/SKILL.md -- Engine architecture and module tree
- `app/views/source_monitor/sources/index.html.erb` (282 lines) -- has 56 lines of filter logic (V1) and repeated filter selects (V5)
- `app/views/source_monitor/items/index.html.erb` -- same filter dropdown pattern
- `app/views/source_monitor/logs/index.html.erb` -- same filter dropdown pattern
- `app/views/source_monitor/sources/_row.html.erb` -- undocumented preload requirements (V3)
- Filter selects share identical Tailwind classes, onchange="this.form.requestSubmit()" behavior, and label styling

## Tasks

### Task 1: Write FilterDropdownComponent test (TDD red) and implement

Create `test/components/source_monitor/filter_dropdown_component_test.rb`:
- Test renders label text
- Test renders select with correct param name
- Test renders options with correct values
- Test marks selected option when selected_value matches
- Test includes onchange="this.form.requestSubmit()" for auto-submit
- Test renders consistent Tailwind styling classes

Create `app/components/source_monitor/filter_dropdown_component.rb`:
- `initialize(label:, param_name:, options:, selected_value: nil, form: nil)`
- `call` method renders label + select with Tailwind styling
- Auto-submit via `onchange` attribute

Create `app/components/source_monitor/filter_dropdown_component.html.erb` (or use inline `call`).

**Note:** If ViewComponent gem is not yet in the gemspec, add `view_component` to `source_monitor.gemspec` as a runtime dependency. Create `app/components/source_monitor/application_component.rb` base class.

### Task 2: Write SourcesFilterPresenter test (TDD red) and implement

Create `test/presenters/source_monitor/sources_filter_presenter_test.rb`:
- Test `has_any_filter?` returns false when no filters active
- Test `has_any_filter?` returns true when search term present
- Test `has_any_filter?` returns true when dropdown filter active
- Test `active_filter_keys` returns only keys with present values
- Test `filter_labels` returns hash with humanized labels for active filters
- Test `adapter_options` returns distinct scraper adapter values

Create `app/presenters/source_monitor/sources_filter_presenter.rb`:
- `initialize(search_params:, search_term:, fetch_interval_filter:, adapter_options:)`
- Extract filter logic from sources/index.html.erb lines 57-106
- Methods: `has_any_filter?`, `active_filter_keys`, `filter_labels`, `clear_filter_path(key, current_params)`

### Task 3: Update sources/index.html.erb to use component and presenter

Modify `app/views/source_monitor/sources/index.html.erb`:
- Replace inline filter selects with `render SourceMonitor::FilterDropdownComponent.new(...)`
- Replace filter state logic (lines 57-106) with `@filter_presenter` method calls
- Move `adapter_options` query from template to controller (assign to presenter)
- Ensure `import_session_step` frame ID is renamed to `source_monitor_import_step` if present (V12)

Modify `app/controllers/source_monitor/sources_controller.rb` (index action only):
- Query adapter_options in controller
- Build `@filter_presenter = SourceMonitor::SourcesFilterPresenter.new(...)` with search params
- Add code comment documenting row partial preload requirements (V3): item_activity_rates, avg_feed_word_counts, avg_scraped_word_counts

### Task 4: Update items and logs index views to use FilterDropdownComponent

Modify `app/views/source_monitor/items/index.html.erb`:
- Replace inline filter selects with `render SourceMonitor::FilterDropdownComponent.new(...)`

Modify `app/views/source_monitor/logs/index.html.erb`:
- Replace inline filter selects with `render SourceMonitor::FilterDropdownComponent.new(...)`

### Task 5: Verify

- `bin/rails test test/components/` -- all component tests pass
- `bin/rails test test/presenters/source_monitor/sources_filter_presenter_test.rb` -- all pass
- `bin/rails test test/controllers/` -- all controller tests pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
