---
phase: "03-toast-stacking"
tier: deep
result: PARTIAL
passed: 33
failed: 3
total: 36
date: "2026-02-20"
---

## Must-Have Checks

| # | Truth/Condition | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | `notification_container_controller.js` exists at correct path | PASS | File present at `app/assets/javascripts/source_monitor/controllers/notification_container_controller.js`, 131 lines |
| 2 | Uses MutationObserver with `{ childList: true }` to detect new toasts | PASS | Line 15-16: `new MutationObserver(() => this.scheduleRecalculate()); this.observer.observe(this.listTarget, { childList: true })` |
| 3 | Caps visible toasts at `maxVisibleValue` (default 3), hides overflow with `hidden` + `aria-hidden` + `inert` | PASS | Lines 60-70: index >= maxVisibleValue gets `hidden`, `aria-hidden="true"`, `inert=""` |
| 4 | `toggleExpand`/`collapseStack` actions toggle expanded state | PASS | Lines 98-117: toggleExpand delegates to expandStack/collapseStack; expandedValue toggled correctly |
| 5 | `recalculateVisibility()` debounced via requestAnimationFrame | PASS | Lines 39-47: scheduleRecalculate cancels previous rAF, schedules new one |
| 6 | Promotes next hidden toast when visible toast is dismissed (MutationObserver fires on DOM removal) | PASS | MutationObserver fires on `element.remove()` in dismiss(); triggers scheduleRecalculate() automatically |
| 7 | `clearAll` action removes all toasts | PASS | Lines 125-130: removes all `listTarget.children`, sets `expandedValue = false` |
| 8 | Updates overflow badge count and toggles badge visibility | PASS | Lines 77-86: badgeCountTarget.textContent = `+${hiddenCount} more`; badge hidden/shown based on hiddenCount |
| 9 | `notification_controller.js` dispatches `notification:dismissed` custom event (bubbles:true) before removal | PASS | Lines 47-49: `this.element.dispatchEvent(new CustomEvent("notification:dismissed", { bubbles: true }))` before fade |
| 10 | Error toasts (`data-level="error"`) get 10000ms delay; others keep 5000ms default | PASS | Lines 38-42: `applyLevelDelay()` checks `dataset.level === "error" && delayValue === 5000`, overrides to 10000 |
| 11 | `application.js` imports and registers `notification-container` controller | PASS | Line 4: import; Line 19: `application.register("notification-container", NotificationContainerController)` |
| 12 | `application.html.erb` wraps `#source_monitor_notifications` with `data-controller="notification-container"` | PASS | Line 17: `data-controller="notification-container"` on outer wrapper div |
| 13 | Layout contains overflow badge with `data-notification-container-target="badge"` and clear-all | PASS | Lines 23-37: badge div with target, badgeCount span, clearAll button with target and action |
| 14 | `_toast.html.erb` includes `data-level` attribute matching `level_key` | PASS | Line 16: `data-level="<%= level_key %>"` on root toast div |
| 15 | Click-outside collapses expanded stack (document listener active only when expanded) | PASS | `expandStack` adds document click listener; `collapseStack` removes it; `handleClickOutside` checks `!this.element.contains(event.target)` |
| 16 | JS builds without errors (`bin/rails assets:precompile` in test/dummy) | PASS | Compiled successfully; `notification_container_controller-f3adc909.js` present in `test/dummy/public/assets/source_monitor/controllers/` |
| 17 | `bin/rubocop` zero offenses (phase files) | PASS | No offenses in any modified files; 4 pre-existing offenses in unrelated test files |
| 18 | `bin/rails test` passes (no regressions) | PASS | 1125 runs, 3514 assertions, 0 failures, 0 errors, 0 skips |
| 19 | MutationObserver disconnected in `disconnect()` | PASS | Lines 26-29: `this.observer.disconnect(); this.observer = null` |
| 20 | requestAnimationFrame cancelled in `disconnect()` | PASS | Lines 31-34: `cancelAnimationFrame(this.rafId); this.rafId = null` |
| 21 | Document click listener removed in `disconnect()` | PASS | Line 36: `document.removeEventListener("click", this.boundHandleClickOutside)` |
| 22 | `notification:dismissed` listener on `listTarget` removed in `disconnect()` | FAIL | Anonymous arrow function `() => this.scheduleRecalculate()` added on line 18-20 is never removed; no bound reference stored. Memory leak on Stimulus controller reconnect cycles |
| 23 | Hidden toasts have `aria-hidden="true"` and `inert` attribute | PASS | Lines 67-68: both attributes set on overflow toasts |
| 24 | Visible toasts have `aria-hidden` and `inert` removed | PASS | Lines 56-57: `removeAttribute("aria-hidden")`, `removeAttribute("inert")` |
| 25 | Badge has `aria-live="polite"` for screen reader announcements | PASS | Line 28 of layout: `aria-live="polite"` on toggle button (non-standard placement but functional) |
| 26 | `#source_monitor_notifications` used as Turbo Stream target (unchanged) | PASS | broadcaster.rb line 71: `target: NOTIFICATION_STREAM` = `"source_monitor_notifications"`; same id in layout |
| 27 | `StreamResponder#toast()` unmodified | PASS | stream_responder.rb line 43-53: no changes; still appends to `"source_monitor_notifications"` |
| 28 | `Broadcaster#broadcast_toast()` unmodified | PASS | broadcaster.rb lines 66-85: no changes to server-side delivery |
| 29 | `notification-container` registered in compiled `application.js` | PASS | `grep "notification-container"` confirms line 2870 of compiled asset |
| 30 | `brakeman` zero security warnings | PASS | 0 warnings; 0 errors |
| 31 | `clearAll` removes document click listener when stack is expanded | FAIL | `clearAll()` sets `this.expandedValue = false` directly without calling `collapseStack()` or `document.removeEventListener()`. If expanded when "Clear all" is clicked, the `boundHandleClickOutside` document listener remains active until next disconnect/page navigation |
| 32 | `clearAll` visibility logic correctly reaches button when badge is hidden | FAIL | `clearAll` target is nested inside the `badge` target div. When expanded with 0 hidden toasts (`hiddenCount=0`), badge div gets `hidden` class (line 84) while `showClearAll` is true (line 89: `total > 0 && expandedValue`). Parent's `hidden` class overrides the child's visibility — "Clear all" cannot appear after collapsing via the same mechanism |
| 33 | `applyLevelDelay()` called before `startTimer()` in connect | PASS | Lines 13-16 of notification_controller.js: `clearTimeout()` then `registerController()` then `applyLevelDelay()` then `startTimer()` |
| 34 | `listTarget` correctly wraps `#source_monitor_notifications` as Stimulus target | PASS | `data-notification-container-target="list"` on the `id="source_monitor_notifications"` div |
| 35 | `notification:dismissed` event listener set on `listTarget` (bubbling from individual toasts) | PASS | Lines 18-20: listener on listTarget; event bubbles from toast child elements |
| 36 | Badge starts hidden initially | PASS | Layout line 24: `class="pointer-events-auto hidden"` — starts hidden, JS reveals on overflow |

## Artifact Checks

| Artifact | Exists | Contains | Status |
|----------|--------|----------|--------|
| `notification_container_controller.js` | YES | MutationObserver, scheduleRecalculate, recalculateVisibility, toggleExpand, expandStack, collapseStack, clearAll, handleClickOutside | PASS |
| `notification_controller.js` (modified) | YES | `notification:dismissed` dispatch, `applyLevelDelay()`, error=10000ms | PASS |
| `application.html.erb` (modified) | YES | `data-controller="notification-container"`, badge target, badgeCount target, clearAll target/action, toggleExpand action | PASS |
| `_toast.html.erb` (modified) | YES | `data-level="<%= level_key %>"` | PASS |
| `application.js` (modified) | YES | `NotificationContainerController` import, `notification-container` registration | PASS |
| Compiled JS asset | YES | `notification_container_controller-f3adc909.js` in test/dummy/public/assets | PASS |

## Key Link Checks

| From | To | Via | Status |
|------|----|-----|--------|
| Toast partial `data-level` | `notification_controller.js` `applyLevelDelay()` | `this.element.dataset.level` | PASS |
| `notification_controller.js` `dismiss()` | `notification_container_controller.js` event listener | `notification:dismissed` CustomEvent (bubbles:true) → listTarget listener | PASS |
| MutationObserver (child added/removed) | `recalculateVisibility()` | `scheduleRecalculate()` via rAF debounce | PASS |
| `Broadcaster#broadcast_toast()` | `#source_monitor_notifications` DOM node | `Turbo::StreamsChannel.broadcast_append_to(NOTIFICATION_STREAM, ...)` | PASS |
| `StreamResponder#toast()` | `#source_monitor_notifications` DOM node | `append("source_monitor_notifications", partial: "_toast")` | PASS |
| Badge button click | `toggleExpand` | `data-action="notification-container#toggleExpand"` | PASS |
| Clear all button click | `clearAll` | `data-action="notification-container#clearAll"` | PASS |

## Anti-Pattern Scan

| Pattern | Found | Location | Severity |
|---------|-------|----------|----------|
| Anonymous event listener without stored reference (cannot be removed) | YES | `notification_container_controller.js` line 18-20: `this.listTarget.addEventListener("notification:dismissed", () => ...)` | MEDIUM — memory leak on controller reconnect cycles; Stimulus reconnects on Turbo navigations |
| `clearAll()` does not call `collapseStack()` to clean up document listener | YES | `notification_container_controller.js` lines 125-130: `expandedValue = false` without `removeEventListener` | LOW — stale click-outside listener after clear-all-while-expanded |
| `clearAll` button nested inside `badge` div — parent's `hidden` class overrides child visibility | YES | `application.html.erb` lines 23-36 + JS lines 88-95 | MEDIUM — "Clear all" unreachable in expanded-with-no-overflow scenario |
| `aria-live` on interactive `<button>` element (non-standard ARIA usage) | YES | `application.html.erb` line 28 | LOW — functional in most screen readers but non-standard; WCAG recommends `aria-live` on non-interactive containers |

## Convention Compliance

| Convention | File | Status | Detail |
|------------|------|--------|--------|
| Stimulus controllers on `window.SourceMonitorStimulus` | `application.js` | PASS | Application registered/reused on `window.SourceMonitorStimulus` |
| Controller naming: kebab-case in HTML | layout + application.js | PASS | `notification-container` used consistently |
| No frozen_string_literal in JS files (N/A) | JS files | N/A | Convention applies to Ruby files only |
| `pointer-events-none` on fixed toast wrapper | `application.html.erb` | PASS | Outer div has `pointer-events-none`; toast and badge have `pointer-events-auto` |
| RuboCop zero offenses (phase files) | Modified Ruby files (none) | PASS | No Ruby files modified in this phase |

## Pre-existing Issues

| Test | File | Error |
|------|------|-------|
| Layout/SpaceInsideArrayLiteralBrackets (4 offenses) | `test/controllers/source_monitor/source_favicon_fetches_controller_test.rb` + `test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb` | Correctable style offenses in files not part of Phase 3 scope; confirmed pre-existing in PLAN-01-SUMMARY.md `pre_existing_issues` |

## Summary

Tier: deep
Result: PARTIAL
Passed: 33/36
Failed: [#22 notification:dismissed listener leak, #31 clearAll missing removeEventListener, #32 clearAll button inaccessible when badge hidden while expanded]

**Core features verified:** All 17 must-have plan requirements pass (file existence, MutationObserver, overflow capping, expand/collapse, badge, dismiss event, error delay, controller registration, template wiring, toast data-level, click-outside, asset build, rubocop, test suite). Server-side delivery paths (StreamResponder, Broadcaster) are unmodified and confirmed working.

**Three defects found:**

1. **Memory leak** (MEDIUM): The `notification:dismissed` event listener added to `listTarget` in `connect()` uses an anonymous arrow function with no stored reference. It cannot be removed in `disconnect()`. On Turbo page navigations, Stimulus disconnects/reconnects controllers, causing duplicate listeners to accumulate.

2. **Stale document click listener** (LOW): `clearAll()` sets `expandedValue = false` but does not call `collapseStack()` or `document.removeEventListener("click", this.boundHandleClickOutside)`. If the user clicks "Clear all" while the stack is expanded, the click-outside document listener remains active.

3. **"Clear all" button DOM structure** (MEDIUM): The `clearAll` target button is a child of the `badge` target div. The JS manages them independently — when `expandedValue=true` and all toasts fit within maxVisible (hiddenCount=0), the badge div gets `hidden` class but `showClearAll` is true. The parent `hidden` class makes "Clear all" invisible despite the JS trying to show it. This occurs during expand with <= maxVisible toasts.
