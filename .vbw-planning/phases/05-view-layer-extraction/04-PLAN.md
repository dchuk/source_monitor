---
phase: "05"
plan: "04"
title: "IconComponent & Dashboard Turbo Stream Granularity"
wave: 2
depends_on: ["01", "03"]
skills_used:
  - viewcomponent-patterns
  - hotwire-patterns
  - tdd-cycle
  - sm-architecture
must_haves:
  - "New SourceMonitor::IconComponent at app/components/source_monitor/icon_component.rb with named icon registry (menu_dots, refresh, chevron_down, external_link, spinner)"
  - "IconComponent test at test/components/source_monitor/icon_component_test.rb covers each icon name, size variants (:sm, :md, :lg), and unknown icon fallback"
  - "Inline SVGs in _row.html.erb, _details.html.erb, _health_status_badge.html.erb replaced with render SourceMonitor::IconComponent.new(...)"
  - "loading_spinner_svg and external_link_icon in application_helper.rb delegate to IconComponent"
  - "Dashboard _stats.html.erb uses per-stat div IDs (source_monitor_stat_{key}) for targeted Turbo Stream updates"
  - "Dashboard::TurboBroadcaster updated to broadcast individual stat updates instead of full _stats partial"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 04: IconComponent & Dashboard Turbo Stream Granularity

## Objective

Create an `IconComponent` to centralize inline SVG repetition across 5+ files (V9), and split dashboard stat updates into per-stat Turbo Streams for targeted re-rendering (V4). This plan runs in wave 2 because it modifies `_details.html.erb` (changed by Plan 01) and `_row.html.erb`/`_health_status_badge.html.erb` (changed by Plan 03).

## Context

- @.claude/skills/viewcomponent-patterns/SKILL.md -- ViewComponent TDD patterns
- @.claude/skills/hotwire-patterns/SKILL.md -- Turbo Stream targeted updates
- @.claude/skills/tdd-cycle/SKILL.md -- TDD workflow
- @.claude/skills/sm-architecture/SKILL.md -- Dashboard module (TurboBroadcaster, Queries)
- SVGs scattered across: `_row.html.erb` (menu dots), `_details.html.erb` (refresh), `_health_status_badge.html.erb` (chevron down), `application_helper.rb` (external link, spinner)
- `app/views/source_monitor/dashboard/_stats.html.erb` re-renders all 5 stat cards on any change (V4)
- `lib/source_monitor/dashboard/turbo_broadcaster.rb` broadcasts full stats partial

## Tasks

### Task 1: Write IconComponent tests (TDD red) and implement

Create `test/components/source_monitor/icon_component_test.rb`:
- Test renders SVG element for known icon names (:menu_dots, :refresh, :chevron_down, :external_link, :spinner)
- Test size variants: `:sm` -> "h-4 w-4", `:md` -> "h-5 w-5", `:lg` -> "h-6 w-6"
- Test defaults to `:md` size
- Test unknown icon name renders empty string or raises ArgumentError
- Test includes `aria-hidden="true"` attribute
- Test spinner icon includes animation class

Create `app/components/source_monitor/icon_component.rb`:
- ICONS constant: hash mapping symbol names to SVG path data
- SIZE_CLASSES constant: hash mapping size symbols to Tailwind classes
- `initialize(name, size: :md, css_class: nil)`
- `call` renders full SVG tag with icon path, size classes, aria-hidden, and optional extra CSS classes
- Register icons: `:menu_dots`, `:refresh`, `:chevron_down`, `:external_link`, `:spinner`

### Task 2: Replace inline SVGs with IconComponent

Modify `app/views/source_monitor/sources/_row.html.erb`:
- Replace 3-dot menu SVG (lines ~114-117) with `render SourceMonitor::IconComponent.new(:menu_dots)`

Modify `app/views/source_monitor/sources/_details.html.erb`:
- Replace refresh SVG (lines ~31-33) with `render SourceMonitor::IconComponent.new(:refresh, size: :sm)`

Modify `app/views/source_monitor/sources/_health_status_badge.html.erb`:
- Replace chevron-down SVG (lines ~17-19) with `render SourceMonitor::IconComponent.new(:chevron_down, size: :sm)`

Modify `app/helpers/source_monitor/application_helper.rb`:
- Update `loading_spinner_svg` to delegate to `render SourceMonitor::IconComponent.new(:spinner, size: :md)` or keep as helper that calls the component
- Update `external_link_icon` (private) to use IconComponent internally

### Task 3: Split dashboard stats into per-stat Turbo Streams

Modify `app/views/source_monitor/dashboard/_stats.html.erb`:
- Give each stat card wrapper a unique ID: `source_monitor_stat_total_sources`, `source_monitor_stat_active_sources`, `source_monitor_stat_failed_sources`, etc.
- Keep grid layout in parent `_stats.html.erb`

Modify `app/views/source_monitor/dashboard/_stat_card.html.erb`:
- Wrap content in a div with the stat-specific ID

Modify `lib/source_monitor/dashboard/turbo_broadcaster.rb`:
- Instead of broadcasting entire `_stats` partial, broadcast individual stat card updates
- Use `turbo_stream.replace "source_monitor_stat_#{key}"` for each changed stat
- Compare previous and current stat values to only broadcast changed stats (or broadcast all individually -- simpler approach)

### Task 4: Write dashboard broadcaster tests for granular updates

Update or create tests for `TurboBroadcaster`:
- Test that broadcasting stats sends individual stat card updates (not full _stats partial)
- Test that each stat card has the correct unique ID
- Test that stat card rendering produces expected HTML structure

### Task 5: Verify

- `bin/rails test test/components/source_monitor/icon_component_test.rb` -- all pass
- `bin/rails test test/lib/source_monitor/dashboard/` -- dashboard tests pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
- Verify no remaining inline SVGs in modified files: `grep -c "<svg" app/views/source_monitor/sources/_row.html.erb` should show reduced count
