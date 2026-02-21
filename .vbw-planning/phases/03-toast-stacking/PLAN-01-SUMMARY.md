---
phase: 3
plan: 1
title: "Toast Stacking: Container Controller, Templates, and Integration"
status: complete
tasks_completed: 4
tasks_total: 4
commits:
  - hash: 6f2b77b
    message: "feat(toast): add notification container controller for toast stacking"
  - hash: 95d96c7
    message: "feat(toast): add dismiss event dispatch and error delay override"
  - hash: 493db3b
    message: "feat(toast): wire container controller in layout and add data-level to toast"
  - hash: 6304ef6
    message: "feat(toast): register notification-container controller in application.js"
deviations: none
pre_existing_issues:
  - file: test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb
    error: "Layout/SpaceInsideArrayLiteralBrackets (4 offenses in unmodified file)"
---

## What Was Built

- New `notification_container_controller.js` Stimulus controller: MutationObserver-based toast overflow capping (max 3 visible), expand/collapse with click-outside, "+N more" badge, "Clear all" action, debounced recalculation via requestAnimationFrame, accessibility (aria-hidden + inert on hidden toasts)
- Modified `notification_controller.js`: dispatches `notification:dismissed` custom event before fade-out, error-level toasts get 10s auto-dismiss (vs 5s default)
- Layout template wired with `data-controller="notification-container"`, list target, badge with count, and clear-all button
- Toast partial includes `data-level` attribute for error delay detection
- Controller registered in `application.js`

## Files Modified

- `app/assets/javascripts/source_monitor/controllers/notification_container_controller.js` (CREATE, 131 lines)
- `app/assets/javascripts/source_monitor/controllers/notification_controller.js` (MODIFY, +11 lines)
- `app/views/layouts/source_monitor/application.html.erb` (MODIFY, +22/-2 lines)
- `app/views/source_monitor/shared/_toast.html.erb` (MODIFY, +1 line)
- `app/assets/javascripts/source_monitor/application.js` (MODIFY, +2 lines)
