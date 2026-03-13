---
phase: "05"
plan: "02"
title: "Remove warning_threshold from HealthSettings"
wave: 1
depends_on: []
must_haves:
  - "warning_threshold removed from HealthSettings attr_accessor and reset!"
  - "No config.warning_threshold references remain in health_settings.rb"
---

# Plan 02: Remove warning_threshold from HealthSettings

## Goal
Remove the `warning_threshold` configuration setting since the simplified 4-status model only uses `healthy_threshold` and `auto_pause_threshold` as boundary points.

## Tasks

### Task 1: Remove warning_threshold from HealthSettings
**Files:** `lib/source_monitor/configuration/health_settings.rb`

- Remove `warning_threshold` from the `attr_accessor` list
- Remove `@warning_threshold = 0.5` from `reset!`

### Task 2: Remove warning_threshold from configuration test
**Files:** `test/lib/source_monitor/configuration_test.rb`

Search for any test that references `warning_threshold` in the configuration test and remove or update it. This setting is being removed entirely.

### Task 3: Check initializer template for warning_threshold reference
**Files:** `lib/source_monitor/setup/install_generator.rb` or related template files

Search for `warning_threshold` in the install generator templates and remove any reference. Also check `examples/` and `docs/` for references.
