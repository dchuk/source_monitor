---
phase: "03"
plan: "02"
title: "Move Favicon Cooldown to Source Model"
status: complete
---

## What Was Built
Added Source#clear_favicon_cooldown! instance method to move business logic from controller to model. Updated SourceFaviconFetchesController to use model method.

## Commits
- 133d87e refactor(models): move favicon cooldown logic from controller to Source model

## Tasks Completed
1. Added 4 unit tests for Source#clear_favicon_cooldown! (key present, key absent, empty metadata, preserving other keys)
2. Added clear_favicon_cooldown! to Source model using metadata.except with update_column
3. Updated SourceFaviconFetchesController to call @source.clear_favicon_cooldown! and removed private method
4. Verified 42 related tests pass

## Files Modified
- app/models/source_monitor/source.rb
- app/controllers/source_monitor/source_favicon_fetches_controller.rb
- test/models/source_monitor/source_test.rb

## Deviations
- Plan called for "nil metadata" test but DB has NOT NULL constraint on metadata; tested empty hash instead.
