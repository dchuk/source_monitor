---
phase: "05"
plan: "04"
title: "IconComponent & Dashboard Turbo Stream Granularity"
status: complete
wave: 2
commits: 5
tests_before: 1551
tests_after: 1551
test_failures: 0
rubocop_offenses: 0
---

## What Was Built

- IconComponent with 5 named icons (menu_dots, refresh, chevron_down, external_link, spinner), 3 size variants (sm/md/lg), and css_class override support
- Replaced all inline SVGs in _row.html.erb, _details.html.erb, _health_status_badge.html.erb with IconComponent renders
- Delegated loading_spinner_svg and external_link_icon helpers to IconComponent
- Dashboard stat cards now have per-stat unique IDs (source_monitor_stat_{key})
- TurboBroadcaster sends 5 individual stat card replacements instead of one full _stats partial broadcast

## Commits

- `caa4e69` feat(05-04): add IconComponent with named icon registry
- `4c56789` refactor(05-04): replace inline SVGs with IconComponent
- `35cd427` feat(05-04): split dashboard stats into per-stat Turbo Streams
- `3e315d9` test(05-04): add tests for granular dashboard stat broadcasting
- `35b3560` style(05-04): fix RuboCop array bracket spacing in IconComponent

## Tasks Completed

- Task 1: IconComponent with test suite (13 tests, 18 assertions)
- Task 2: Inline SVG replacement in 4 files (0 inline SVGs remaining in modified views)
- Task 3: Per-stat Turbo Stream broadcasting with STAT_CARDS constant
- Task 4: Dashboard broadcaster tests (5 new tests for granular updates)
- Task 5: Full verification (1551 tests pass, 0 RuboCop offenses)

## Files Modified

- `app/components/source_monitor/icon_component.rb` -- new IconComponent
- `test/components/source_monitor/icon_component_test.rb` -- IconComponent tests
- `app/views/source_monitor/sources/_row.html.erb` -- menu_dots SVG replaced
- `app/views/source_monitor/sources/_details.html.erb` -- refresh SVG replaced
- `app/views/source_monitor/sources/_health_status_badge.html.erb` -- chevron_down SVG replaced
- `app/helpers/source_monitor/application_helper.rb` -- loading_spinner_svg and external_link_icon delegate to IconComponent
- `app/views/source_monitor/dashboard/_stats.html.erb` -- individual stat card renders with key
- `app/views/source_monitor/dashboard/_stat_card.html.erb` -- unique ID per stat card
- `lib/source_monitor/dashboard/turbo_broadcaster.rb` -- per-stat broadcast with STAT_CARDS
- `test/lib/source_monitor/dashboard/turbo_broadcaster_test.rb` -- 5 new granular broadcast tests

## Deviations

- DEVN-01: Added `size: nil` support to IconComponent so loading_spinner_svg and external_link_icon callers can provide full css_class without conflicting size classes. Minor addition, no scope change.
