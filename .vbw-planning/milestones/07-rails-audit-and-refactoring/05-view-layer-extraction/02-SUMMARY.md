---
phase: "05"
plan: "02"
title: "FilterDropdownComponent & SourcesFilterPresenter"
status: complete
---

## What Was Built

- **FilterDropdownComponent**: Reusable ViewComponent for labeled filter selects with auto-submit, consistent Tailwind styling, and Ransack form builder support. Added `view_component` (~> 3.0) as a runtime engine dependency.
- **SourcesFilterPresenter**: Plain Ruby presenter encapsulating filter state logic (active filter detection, label generation, adapter options) previously inline in the sources index template.
- **View refactoring**: Sources index uses component for all 5 filter dropdowns and presenter for filter state banner. Logs index uses component for timeframe dropdown. Items index had no applicable dropdowns.

## Commits

| Hash | Message |
|------|---------|
| `cafefc2` | feat(05-02): add FilterDropdownComponent with ViewComponent |
| `795b7b8` | feat(05-02): add SourcesFilterPresenter for filter state logic |
| `140d0e4` | refactor(05-02): use FilterDropdownComponent and SourcesFilterPresenter in sources index |
| `c3360c6` | refactor(05-02): use FilterDropdownComponent in logs index |
| `489277b` | style(05-02): fix rubocop offenses in component files |

## Tasks Completed

1. FilterDropdownComponent test (8 tests) and implementation -- GREEN
2. SourcesFilterPresenter test (11 tests) and implementation -- GREEN
3. Sources index refactored to use component and presenter; controller builds presenter with adapter_options query and row preload comment
4. Logs index timeframe select replaced with FilterDropdownComponent; items index unchanged (no dropdown filters)
5. Verification: 1533 tests pass, 0 failures; rubocop clean on all modified files

## Files Modified

- `source_monitor.gemspec` -- added view_component dependency
- `Gemfile.lock` -- updated lockfile
- `app/components/source_monitor/application_component.rb` -- new base component
- `app/components/source_monitor/filter_dropdown_component.rb` -- new filter dropdown component
- `app/presenters/source_monitor/sources_filter_presenter.rb` -- new filter state presenter
- `app/views/source_monitor/sources/index.html.erb` -- replaced inline filters with component/presenter
- `app/views/source_monitor/logs/index.html.erb` -- replaced timeframe select with component
- `app/controllers/source_monitor/sources_controller.rb` -- builds @filter_presenter, moved adapter_options query
- `test/components/source_monitor/filter_dropdown_component_test.rb` -- 8 component tests
- `test/presenters/source_monitor/sources_filter_presenter_test.rb` -- 11 presenter tests

## Deviations

- Items index (`items/index.html.erb`) has no dropdown filter selects (only a search bar), so no FilterDropdownComponent was applied there. The plan mentioned it should use the component "for their filter selects" but none exist. This is a DEVN-01 (minor scope clarification, no escalation needed).
- Logs index has button-group filters (status/type) and form fields (search, datetimes, IDs) that don't match the dropdown pattern. Only the timeframe select was replaced. This is expected behavior, not a deviation.
