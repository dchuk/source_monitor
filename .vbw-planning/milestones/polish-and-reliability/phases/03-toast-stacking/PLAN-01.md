---
phase: 3
plan: 1
title: "Toast Stacking: Container Controller, Templates, and Integration"
wave: 1
depends_on: []
must_haves:
  - "notification_container_controller.js exists at app/assets/javascripts/source_monitor/controllers/notification_container_controller.js"
  - "notification_container_controller uses MutationObserver with childList:true to detect new toasts"
  - "notification_container_controller caps visible toasts at maxVisibleValue (default 3), hides overflow with hidden class + aria-hidden + inert"
  - "notification_container_controller toggleExpand/collapseStack actions toggle expanded state"
  - "notification_container_controller recalculateVisibility() debounced via requestAnimationFrame"
  - "notification_container_controller promotes next hidden toast when a visible toast is dismissed (MutationObserver fires on DOM removal)"
  - "notification_container_controller clearAll action removes all toasts"
  - "notification_container_controller updates overflow badge count and toggles badge visibility"
  - "notification_controller.js dispatches 'notification:dismissed' custom event (bubbles:true) before removal"
  - "Error toasts (data-level='error') get 10000ms delay; others keep 5000ms default"
  - "application.js imports and registers notification-container controller"
  - "application.html.erb wraps #source_monitor_notifications with data-controller='notification-container'"
  - "application.html.erb contains overflow badge with data-notification-container-target='badge' and clear-all link"
  - "_toast.html.erb includes data-level attribute matching level_key"
  - "Click-outside collapses expanded stack (document listener, active only when expanded)"
  - "JS builds without errors (bin/rails assets:precompile in test/dummy)"
  - "bin/rubocop zero offenses"
  - "bin/rails test passes (no regressions)"
skills_used: []
---

# Plan 01: Toast Stacking -- Full Implementation

## Objective

Implement the complete toast stacking feature: a new `notification_container_controller.js` Stimulus controller that wraps the notification container, observes child mutations, caps visible toasts at a configurable max, manages expand/collapse state with click-outside, promotes hidden toasts on dismissal, and provides a "Clear all" action. Update the existing `notification_controller.js` to dispatch a dismiss event and support error-level delay. Wire everything together in the layout template with badge/clear-all HTML and add `data-level` to the toast partial. Covers REQ-TOAST-01, REQ-TOAST-02, REQ-TOAST-03, REQ-TOAST-04.

## Context

- `@app/assets/javascripts/source_monitor/controllers/notification_controller.js` -- existing per-toast Stimulus controller. Has `dismiss()` that fades out and removes element after 200ms. Delay default is 5000ms via Stimulus value. Must add custom event dispatch + error delay override.
- `@app/assets/javascripts/source_monitor/application.js` -- Stimulus registration hub. 6 controllers registered. Must add notification-container import + register.
- `@app/views/layouts/source_monitor/application.html.erb` lines 16-18 -- notification container: `<div id="source_monitor_notifications" class="flex w-full max-w-sm flex-col gap-3">` inside a fixed positioned wrapper. Must add `data-controller` and Stimulus target/action markup, plus badge and clear-all HTML.
- `@app/views/source_monitor/shared/_toast.html.erb` -- toast partial with level-based Tailwind classes. Must add `data-level` attribute for error delay detection.
- `@lib/source_monitor/turbo_streams/stream_responder.rb` -- `toast()` appends to `source_monitor_notifications`. NO CHANGES NEEDED (server-side unaffected).
- `@lib/source_monitor/realtime/broadcaster.rb` -- `broadcast_toast()` appends via ActionCable. NO CHANGES NEEDED.
- `@.vbw-planning/phases/03-toast-stacking/03-RESEARCH.md` -- research findings on MutationObserver, debounce, accessibility.

## Tasks

### Task 1: Create notification_container_controller.js

**Files:** CREATE `app/assets/javascripts/source_monitor/controllers/notification_container_controller.js`

Create a Stimulus controller that manages toast overflow capping, expand/collapse, and clear-all.

**Stimulus API:**
- **Values:** `maxVisible` (Number, default: 3), `expanded` (Boolean, default: false)
- **Targets:** `list` (the toast container div), `badge` (overflow indicator), `badgeCount` (count text span), `clearAll` (clear-all link)
- **Actions:** `toggleExpand` (badge click), `clearAll` (clear-all click)

**Core implementation:**

1. **`connect()`**: Set up MutationObserver on `listTarget` with `{ childList: true }`. Bind click-outside handler and `notification:dismissed` event listener on `listTarget`. Call `recalculateVisibility()`.

2. **`disconnect()`**: Clean up observer, cancel any pending rAF, remove document click listener, remove event listener.

3. **`scheduleRecalculate()`**: Debounce via `requestAnimationFrame` -- cancel previous rAF if pending, schedule new one that calls `recalculateVisibility()`.

4. **`recalculateVisibility()`**: Core logic:
   - Get all direct children of `listTarget` (toast elements)
   - If `expandedValue` is true: show all toasts (remove `hidden`, `aria-hidden`, `inert`)
   - If not expanded: show first `maxVisibleValue`, hide the rest with `hidden` class + `aria-hidden="true"` + `inert` attribute
   - Calculate `hiddenCount = Math.max(0, total - maxVisibleValue)` (when not expanded); 0 when expanded
   - If `hasBadgeTarget`: update `badgeCountTarget.textContent` to `+${hiddenCount} more`; toggle badge visibility based on `hiddenCount > 0`
   - If `hasClearAllTarget`: toggle clear-all visibility based on `total > 0 && (hiddenCount > 0 || expandedValue)`

5. **`toggleExpand(event)`**: Prevent default. If expanded, call `collapseStack()`; else call `expandStack()`.

6. **`expandStack()`**: Set `expandedValue = true`. Call `recalculateVisibility()`. Add document click-outside listener.

7. **`collapseStack()`**: Set `expandedValue = false`. Remove document click-outside listener. Call `recalculateVisibility()`.

8. **`handleClickOutside(event)`**: If `event.target` is not within `this.element`, call `collapseStack()`.

9. **`clearAll(event)`**: Prevent default. Get all direct children of `listTarget`, remove each one. Set `expandedValue = false`. (MutationObserver will fire and trigger `scheduleRecalculate` automatically.)

**Accessibility:**
- Hidden toasts get `aria-hidden="true"` and `inert` attribute (prevents focus/interaction)
- Visible toasts have these removed
- Badge uses `aria-live="polite"` (set in template)

**Important notes:**
- The `notification:dismissed` custom event fires before DOM removal -- the subsequent DOM removal triggers MutationObserver which schedules recalculate. This naturally handles promote-next-hidden behavior.
- No animation for individual toast show/hide in overflow (toggle `hidden` class). The "slide" effect comes from the flex container naturally reflowing.
- Both Turbo Stream appends and ActionCable broadcasts add children to the same DOM node, so MutationObserver catches both uniformly.

### Task 2: Modify notification_controller.js for dismiss event and error delay

**Files:** MODIFY `app/assets/javascripts/source_monitor/controllers/notification_controller.js`

Two changes to the existing per-toast controller:

1. **Dispatch custom event on dismiss** -- In the `dismiss()` method, before starting the fade-out animation, dispatch a bubbling custom event so the container controller can react immediately:
   ```javascript
   dismiss() {
     if (!this.element) return;
     this.element.dispatchEvent(
       new CustomEvent("notification:dismissed", { bubbles: true })
     );
     this.element.classList.add("opacity-0", "translate-y-2");
     window.setTimeout(() => {
       if (this.element && this.element.remove) {
         this.element.remove();
       }
     }, 200);
   }
   ```

2. **Error delay override** -- Add `applyLevelDelay()` method called at the start of `connect()` (before `startTimer()`). Check `this.element.dataset.level` -- if `"error"` and current `delayValue` is the default 5000, override to 10000:
   ```javascript
   applyLevelDelay() {
     const level = this.element.dataset.level;
     if (level === "error" && this.delayValue === 5000) {
       this.delayValue = 10000;
     }
   }
   ```
   Call this in `connect()` after clearing timeout, before `startTimer()`.

### Task 3: Update templates -- layout wrapper, badge HTML, toast data-level

**Files:** MODIFY `app/views/layouts/source_monitor/application.html.erb`, MODIFY `app/views/source_monitor/shared/_toast.html.erb`

**Layout changes** (lines 16-18 of application.html.erb):

Replace the current notification container markup:
```html
<div class="pointer-events-none fixed inset-x-0 top-4 z-50 flex justify-end px-6">
  <div id="source_monitor_notifications" class="flex w-full max-w-sm flex-col gap-3"></div>
</div>
```

With the container-controller-wrapped version:
```html
<div class="pointer-events-none fixed inset-x-0 top-4 z-50 flex justify-end px-6"
     data-controller="notification-container">
  <div class="flex w-full max-w-sm flex-col items-end gap-3">
    <div id="source_monitor_notifications"
         data-notification-container-target="list"
         class="flex w-full flex-col gap-3">
    </div>
    <div data-notification-container-target="badge"
         class="pointer-events-auto hidden">
      <button type="button"
              data-action="notification-container#toggleExpand"
              class="inline-flex items-center gap-1.5 rounded-full bg-slate-700 px-3 py-1 text-xs font-medium text-white shadow-lg transition hover:bg-slate-600"
              aria-live="polite">
        <span data-notification-container-target="badgeCount">+0 more</span>
      </button>
      <button type="button"
              data-action="notification-container#clearAll"
              data-notification-container-target="clearAll"
              class="ml-1 text-xs font-medium text-slate-400 underline transition hover:text-white">
        Clear all
      </button>
    </div>
  </div>
</div>
```

Key design decisions:
- `data-controller` on the outer fixed wrapper (encompasses both the toast list and the badge)
- `listTarget` is the existing `#source_monitor_notifications` div (Turbo Streams and ActionCable append here)
- Badge and clear-all are siblings BELOW the list (appear at the bottom of the stack)
- Badge starts `hidden` (toggled by controller when overflow exists)
- `pointer-events-auto` on the badge div so it's clickable despite the `pointer-events-none` parent
- `aria-live="polite"` on the button for screen reader announcements

**Toast partial changes** (_toast.html.erb):

Add `data-level` attribute to the root div so the notification controller can detect error level:
```erb
<div
  data-controller="notification"
  data-notification-delay-value="<%= delay_ms %>"
  data-level="<%= level_key %>"
  class="pointer-events-auto w-full max-w-md rounded-lg border px-4 py-3 shadow-lg transition duration-300 <%= classes %>"
>
```

This is the only change to the partial -- add `data-level="<%= level_key %>"`.

### Task 4: Register controller in application.js, verify build and tests

**Files:** MODIFY `app/assets/javascripts/source_monitor/application.js`

1. Add import after existing notification import (line 3):
   ```javascript
   import NotificationContainerController from "./controllers/notification_container_controller";
   ```

2. Add registration after existing notification registration (line 17):
   ```javascript
   application.register("notification-container", NotificationContainerController);
   ```

3. Verify everything builds and passes:
   ```bash
   cd test/dummy && bin/rails assets:precompile 2>&1 | tail -20
   cd /path/to/source_monitor && bin/rubocop
   cd /path/to/source_monitor && bin/rails test
   ```

   Ensure:
   - No JS import errors or build failures
   - RuboCop zero offenses
   - All tests pass (no regressions from template changes)

## Files

| Action | Path |
|--------|------|
| CREATE | `app/assets/javascripts/source_monitor/controllers/notification_container_controller.js` |
| MODIFY | `app/assets/javascripts/source_monitor/controllers/notification_controller.js` |
| MODIFY | `app/views/layouts/source_monitor/application.html.erb` |
| MODIFY | `app/views/source_monitor/shared/_toast.html.erb` |
| MODIFY | `app/assets/javascripts/source_monitor/application.js` |

## Verification

```bash
# JS build check
cd test/dummy && bin/rails assets:precompile 2>&1 | tail -20

# Ruby lint
bin/rubocop

# Full test suite (no regressions)
bin/rails test

# Spot-check: container controller exists and has MutationObserver
grep -c "MutationObserver" app/assets/javascripts/source_monitor/controllers/notification_container_controller.js

# Spot-check: dismiss event in notification controller
grep "notification:dismissed" app/assets/javascripts/source_monitor/controllers/notification_controller.js

# Spot-check: data-level in toast partial
grep "data-level" app/views/source_monitor/shared/_toast.html.erb

# Spot-check: container controller registered
grep "notification-container" app/assets/javascripts/source_monitor/application.js

# Spot-check: layout has controller wired
grep "notification-container" app/views/layouts/source_monitor/application.html.erb
```

## Success Criteria

- No more than 3 toasts visible simultaneously (configurable via `maxVisibleValue`)
- Overflow badge shows "+N more" count and appears only when overflow exists
- Click badge expands stack (shows all toasts), click again or outside collapses
- Auto-dismiss still works; stack count updates as toasts expire/are removed
- Dismissing a visible toast promotes next hidden one (natural from MutationObserver recalculate)
- "Clear all" link removes all toasts at once
- Error toasts get 10s auto-dismiss delay (vs 5s default)
- Both Turbo Stream inline and ActionCable broadcast delivery paths work unmodified
- JS builds without errors
- RuboCop zero offenses
- All existing tests pass
