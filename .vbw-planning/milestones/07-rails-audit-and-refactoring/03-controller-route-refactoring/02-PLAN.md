---
phase: "03"
plan: "02"
title: "Move Favicon Cooldown to Source Model"
wave: 1
depends_on: []
must_haves:
  - "Source model has clear_favicon_cooldown! instance method"
  - "clear_favicon_cooldown! removes favicon_last_attempted_at from metadata hash"
  - "SourceFaviconFetchesController calls @source.clear_favicon_cooldown! instead of inline logic"
  - "Controller no longer has clear_favicon_cooldown private method"
  - "Unit test for Source#clear_favicon_cooldown! covers: key present, key absent, nil metadata"
  - "Existing source_favicon_fetches_controller_test.rb still passes"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 02: Move Favicon Cooldown to Source Model

## Objective

Move favicon cooldown clearing logic from SourceFaviconFetchesController into the Source model (C2), following the project convention that business logic lives in models.

## Context

- `app/controllers/source_monitor/source_favicon_fetches_controller.rb:33-36` has `clear_favicon_cooldown` that directly manipulates `metadata` hash and calls `update_column`
- `app/models/source_monitor/source.rb` already has `attribute :metadata, default: -> { {} }` (line 35)
- `FaviconFetchJob` also checks `favicon_last_attempted_at` in metadata -- having the clear method on the model centralizes this concern
- The controller bypasses model callbacks with `update_column` -- the model method should preserve this behavior (it's intentional for cooldown clearing)

## Tasks

### Task 1: Write Source#clear_favicon_cooldown! tests (TDD red)

Add tests to `test/models/source_monitor/source_test.rb`:
- Test clears `favicon_last_attempted_at` from metadata when key exists
- Test is a no-op when key is not present (no error)
- Test handles nil metadata gracefully
- Test preserves other metadata keys

### Task 2: Add clear_favicon_cooldown! to Source model

Add to `app/models/source_monitor/source.rb`:
```ruby
def clear_favicon_cooldown!
  metadata_without_cooldown = (metadata || {}).except("favicon_last_attempted_at")
  update_column(:metadata, metadata_without_cooldown)
end
```

### Task 3: Update SourceFaviconFetchesController

In `app/controllers/source_monitor/source_favicon_fetches_controller.rb`:
- Replace `clear_favicon_cooldown(@source)` with `@source.clear_favicon_cooldown!`
- Remove the private `clear_favicon_cooldown` method

### Task 4: Verify

- `bin/rails test` -- all pass
- `bin/rubocop` -- zero offenses
