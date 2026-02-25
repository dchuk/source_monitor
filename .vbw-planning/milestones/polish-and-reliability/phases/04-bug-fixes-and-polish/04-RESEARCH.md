# Phase 4 Research: Bug Fixes & Polish

## Issue 1: OPML Import Warning on Completion

**Files:** `app/views/source_monitor/import_sessions/show.html.erb`, `app/assets/javascripts/source_monitor/controllers/confirm_navigation_controller.js`

**Problem:** The entire show.html.erb wraps in `data-controller="confirm-navigation"`. The controller registers `beforeunload` and `turbo:before-visit` listeners on connect(). When the import completes, the redirect via `StreamActions.redirect` fires `turbo:before-visit`, but confirm-navigation is still mounted — so it intercepts with the "in-progress import" warning.

**Fix:** Add `data-action="submit->confirm-navigation#disable"` to the "Start import" form in `_confirm.html.erb` (line 117) so the guard is removed before the form submits and the redirect fires.

## Issue 2: Alerts Covering Menu Links

**Files:** `app/views/layouts/source_monitor/application.html.erb` (line 16), `app/views/source_monitor/shared/_toast.html.erb`

**Problem:** Notification container uses `fixed inset-x-0 top-4 z-50`. The `top-4` (16px) puts toasts right over the nav header (~56px tall). While the container is `pointer-events-none`, actual toast elements have `pointer-events-auto` and can cover nav links.

**Fix:** Change `top-4` to `top-16` or `top-20` to clear the navbar height. This pushes toasts below the header.

## Issue 3: Dashboard Status Table Column Alignment

**Files:** `app/views/source_monitor/dashboard/_fetch_schedule.html.erb`

**Problem:** Each time-bracket group renders its own `<table>` with independent column widths. Columns are sized by content, so they misalign across tables.

**Fix:** Apply `table-fixed` layout and explicit column widths (e.g., `w-[45%]`, `w-[15%]`, `w-[22%]`, `w-[18%]`) consistently across all tables.

## Issue 4: Delete Sources 500 Error

**Files:** `app/controllers/source_monitor/sources_controller.rb` (lines 76-112), `app/models/source_monitor/source.rb`

**Problem:** `@source.destroy` is called with no error handling. The `dependent: :destroy` chain cascades through items, fetch_logs, scrape_logs, health_check_logs, log_entries. If any association fails (FK constraint, callback error, Active Storage favicon), the 500 propagates.

**Fix:** Wrap destroy in error handling. Also investigate actual error — likely related to favicon Active Storage attachment or log_entries polymorphic association. Add `rescue` with flash error and redirect.

## Issue 5: Published Column Shows "Unpublished"

**Files:** `app/views/source_monitor/items/index.html.erb` (line 94), `lib/source_monitor/pipeline/entry_processor.rb` or similar

**Problem:** `item.published_at ? strftime(...) : "Unpublished"` — if `published_at` is never set during feed import, all items show "Unpublished". The feed parser may not be mapping the published date from feed entries.

**Fix:** Investigate entry processor to find where published_at should be set. If feeds don't always provide dates, fall back to `created_at` for display.
