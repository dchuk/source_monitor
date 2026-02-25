---
phase: 4
plan: 2
title: Source Deletion Fix
wave: 1
depends_on: []
must_haves:
  - Source deletion works without 500 error
  - Engine handles host app FK constraints gracefully
  - Error handling provides useful feedback on failure
---

# Plan 2: Source Deletion Fix

Investigate and fix the 500 error when deleting sources, particularly when host apps extend engine models with additional FK references.

## Tasks

### Task 1: Investigate the destroy cascade

**Files:** `app/models/source_monitor/source.rb`, `app/controllers/source_monitor/sources_controller.rb`

Examine the full `dependent: :destroy` chain on Source:
- `has_many :all_items` (dependent setting?)
- `has_many :fetch_logs` (dependent setting?)
- `has_many :scrape_logs` (dependent setting?)
- `has_many :health_check_logs` (dependent setting?)
- `has_many :log_entries` (dependent setting?)
- `has_one_attached :favicon` (Active Storage)

Check if any association is missing `dependent: :destroy` or if the ordering causes FK violations. Pay special attention to:
1. Active Storage favicon attachment cleanup
2. Whether items have their own dependent associations that cascade further
3. Whether the engine properly handles host-app-added associations

### Task 2: Fix the destroy cascade

Based on investigation findings:
- Ensure all associations have proper `dependent:` options
- Use `dependent: :destroy_async` for large collections if appropriate
- Add a `before_destroy` callback to handle cleanup ordering if needed
- Ensure Active Storage favicon is properly cleaned up

### Task 3: Add error handling to destroy action

**Files:** `app/controllers/source_monitor/sources_controller.rb`

Wrap `@source.destroy` in proper error handling:
```ruby
if @source.destroy
  # existing turbo stream / html response
else
  # error response with useful message
end
```

Also add `rescue ActiveRecord::InvalidForeignKey` to catch host-app FK violations and provide a helpful error message like "Cannot delete source: other records still reference it."

### Task 4: Add tests for destroy action

- Test successful deletion with all dependent records
- Test deletion failure handling (FK violation scenario)
- Test that error messages are user-friendly
- Test both turbo_stream and html response formats

## Acceptance Criteria

- [ ] Deleting a source with items, logs, and favicon works without error
- [ ] FK violations from host app extensions produce a user-friendly error instead of 500
- [ ] Both turbo_stream and html response formats handle success and failure
- [ ] All existing tests pass plus new destroy tests
- [ ] RuboCop zero offenses
