---
phase: 2
plan: "01"
title: config-deprecation-framework
status: complete
---

## Tasks
- [x] Task 1: create-deprecation-registry -- DeprecationRegistry class with register/clear!/entries/registered?, DeprecatedOptionError, SETTINGS_CLASSES mapping for all 11 settings classes
- [x] Task 2: wire-registry-into-configuration-and-autoload -- require in configuration.rb, check_deprecations! method, configure hook
- [x] Task 3: create-deprecation-registry-tests -- 10 tests covering all branches (warning/error/clear/top-level/zero-false-positives/multiple/wiring)
- [x] Task 4: full-suite-verification-and-brakeman -- 1002 runs/0 failures, RuboCop 0 offenses, Brakeman 0 warnings

## Commits
- 5e95f72 feat(02-config-deprecation): create-deprecation-registry
- 12d8b31 feat(02-config-deprecation): wire-registry-into-configuration-and-autoload
- b29c183 test(02-config-deprecation): create-deprecation-registry-tests

## Files Modified
- lib/source_monitor/configuration/deprecation_registry.rb (new -- DeprecationRegistry class + DeprecatedOptionError)
- lib/source_monitor/configuration.rb (added require + check_deprecations! method)
- lib/source_monitor.rb (added config.check_deprecations! in configure)
- test/lib/source_monitor/configuration/deprecation_registry_test.rb (new -- 10 tests)

## Deviations
- DEVN-01: Fixed replacement resolution bug where same-prefix paths (e.g. "http.old_proxy" -> "http.proxy") incorrectly tried to call `self.http` on an HTTPSettings instance. Added `source_prefix` parameter to replacement_setter_for/replacement_getter_for to detect when deprecated and replacement options share the same settings class prefix, resolving directly on `self` instead.
- Pre-existing: ReleasePackagingTest (1 error) fails due to untracked `.vbw-planning/phases/` files in gemspec's `git ls-files` output. Not caused by this plan.
