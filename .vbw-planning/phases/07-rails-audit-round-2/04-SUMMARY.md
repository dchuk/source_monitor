---
phase: "07"
plan: "04"
title: "View Layer & Accessibility"
status: complete
---

## What Was Built
StatusBadgeComponent replacing 12+ duplicated badge patterns (M20), modal WCAG accessibility with role/aria attributes and inert-based focus trapping (M22+M23), inline DB query removal from view templates (M19), shared pagination/form-errors/scrape-test-result partials (L20+L21+L23), FilterDropdown Stimulus migration from inline JS (L27), and Logs index Turbo Frame for partial page updates (M24).

## Commits
- 967f829 feat(07-04): create StatusBadgeComponent for unified status badges (M20)
- 0e583a7 refactor(07-04): replace inline badge markup with StatusBadgeComponent (M20)
- 5873dc1 feat(07-04): add modal accessibility and focus trapping (M22+M23)
- bab9b88 refactor(07-04): move inline queries from views, consolidate partials (M19+L20+L21+L23)
- dafa356 feat(07-04): FilterDropdown Stimulus action + Logs Turbo Frame (L27+M24)
- 63f5cbb test(07-04): update FilterDropdownComponent test for Stimulus action (L27)

## Tasks Completed
- Task 1: Created StatusBadgeComponent with 24 tests covering all status types, sizes, spinner behavior, and fallbacks
- Task 2: Replaced inline badge markup in 6 view templates (sources row/details, dashboard, items details/index, logs index)
- Task 3: Added role="dialog", aria-modal="true", aria-labelledby to both modals; implemented inert-based focus trapping in modal_controller.js
- Task 4: Removed inline DB queries from items/_details and sources/_details; replaced items/logs pagination with shared partial; created _result_content partial for scrape tests; created shared/_form_errors partial
- Task 5: Replaced FilterDropdownComponent inline onchange with Stimulus filter-submit controller; wrapped logs index in Turbo Frame

## Files Modified
- app/components/source_monitor/status_badge_component.rb (new)
- app/components/source_monitor/status_badge_component.html.erb (new)
- app/components/source_monitor/filter_dropdown_component.rb
- app/views/source_monitor/sources/_row.html.erb
- app/views/source_monitor/sources/_details.html.erb
- app/views/source_monitor/sources/_bulk_scrape_modal.html.erb
- app/views/source_monitor/sources/_bulk_scrape_enable_modal.html.erb
- app/views/source_monitor/sources/new.html.erb
- app/views/source_monitor/sources/edit.html.erb
- app/views/source_monitor/dashboard/_recent_activity.html.erb
- app/views/source_monitor/items/_details.html.erb
- app/views/source_monitor/items/index.html.erb
- app/views/source_monitor/logs/index.html.erb
- app/views/source_monitor/shared/_form_errors.html.erb (new)
- app/views/source_monitor/source_scrape_tests/show.html.erb
- app/views/source_monitor/source_scrape_tests/_result.html.erb
- app/views/source_monitor/source_scrape_tests/_result_content.html.erb (new)
- app/assets/javascripts/source_monitor/controllers/modal_controller.js
- app/assets/javascripts/source_monitor/controllers/filter_submit_controller.js (new)
- app/assets/javascripts/source_monitor/application.js
- app/controllers/source_monitor/items_controller.rb
- app/helpers/source_monitor/application_helper.rb
- lib/source_monitor/logs/query.rb
- test/components/source_monitor/status_badge_component_test.rb (new)
- test/components/source_monitor/filter_dropdown_component_test.rb

## Deviations
- Some inline badge spans remain in views for non-status contextual badges (e.g., "Blocked" warning, "Scrape Recommended", retention policy pills, import session step indicators, log type labels). These are not the duplicated status badge pattern targeted by M20 -- they are one-off contextual badges with distinct semantics.
- Sources _details.html.erb inline queries use fallback pattern (@instance_var || inline_query) rather than strictly removing the query, to maintain backward compatibility when the partial is rendered outside the show action.

## Pre-existing Issues
- SourceMonitor::Dashboard::QueriesTest -- 2 errors in clean_source_monitor_tables! (unrelated to view changes)
- SourceMonitor::EventSystemTest -- 2 errors: undefined method 'process_feed_entries' (unrelated API change)
- SourceMonitor::Integration::HostInstallFlowTest -- bundle install failure (environment issue)
- SourceMonitor::ItemContentTest -- 2 errors in Active Storage attachment tests (unrelated)
- SourceMonitor::Favicons::SvgConverterTest -- missing assertion warning (pre-existing)
