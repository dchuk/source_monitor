---
phase: 4
plan: 2
title: Source Deletion Fix
status: complete
completed: 2026-02-22
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 62f8190
deviations: []
---

Fixed 500 error when deleting sources by adding proper error handling for FK constraint violations from host app model extensions.

## What Was Built

- Wrapped `@source.destroy` in begin/rescue with `ActiveRecord::InvalidForeignKey` catch
- Added `handle_destroy_failure` private method supporting both turbo_stream (error toast) and html (flash alert) responses
- FK violations now produce a user-friendly "Cannot delete — other records still reference this source" message instead of a 500 error
- Added 6 new tests covering successful deletion, FK violation handling, and both response formats

## Files Modified

- `app/controllers/source_monitor/sources_controller.rb` -- wrapped destroy in error handling, added `handle_destroy_failure` method
- `test/controllers/source_monitor/sources_controller_test.rb` -- added 6 destroy action tests
