---
phase: "05"
plan: "03"
title: "Dropdown Stabilization & JavaScript Cleanup"
wave: 1
depends_on: []
skills_used:
  - hotwire-patterns
  - tdd-cycle
must_haves:
  - "dropdown_controller.js simplified to single CSS class toggle path (no stimulus-use async loading)"
  - "dropdown_controller.js toggle/hide methods use only this.menuTarget within controller scope (not global selectors)"
  - "Each dropdown instance in _row.html.erb and _health_status_badge.html.erb has unique data-testid attributes for isolation verification"
  - "window.SourceMonitorControllers removed from notification_controller.js -- uses Stimulus outlet or dispatch events instead"
  - "window.SourceMonitorStimulus assignment in application.js wrapped in development-only guard or removed"
  - "All existing controller tests and system tests pass unchanged"
  - "yarn build succeeds with no ESLint errors"
  - "bin/rails test passes"
---

# Plan 03: Dropdown Stabilization & JavaScript Cleanup

## Objective

Simplify the dropdown controller by removing the fragile stimulus-use async loading path (V6), improve dropdown state isolation (V7), and clean up global window namespace pollution (V13). This improves JavaScript maintainability and prevents memory leaks in SPA-like Turbo Drive navigation.

## Context

- @.claude/skills/hotwire-patterns/SKILL.md -- Stimulus controller patterns and best practices
- @.claude/skills/tdd-cycle/SKILL.md -- TDD workflow for verification
- `app/assets/javascripts/source_monitor/controllers/dropdown_controller.js` (110 lines) -- fragile async loading with stimulus-use fallback (V6), shared state between instances (V7)
- `app/assets/javascripts/source_monitor/controllers/notification_controller.js` (63 lines) -- registers on window.SourceMonitorControllers (V13)
- `app/assets/javascripts/source_monitor/application.js` -- exports window.SourceMonitorStimulus (V13)
- `app/views/source_monitor/sources/_row.html.erb` -- dropdown for row actions (lines 109-141)
- `app/views/source_monitor/sources/_health_status_badge.html.erb` -- dropdown for health menu (lines 8-37)
- Code comment on dropdown line 35: "Evaluated for simplification in Phase 20.05.07 - Decision: Keep current implementation." -- This phase overrides that decision with Option A (CSS class toggle only).

## Tasks

### Task 1: Simplify dropdown_controller.js to CSS class toggle only

Rewrite `app/assets/javascripts/source_monitor/controllers/dropdown_controller.js`:
- Remove `loadTransitions()` async method entirely
- Remove `transitionModuleValue`, `hiddenClassValue` value definitions (keep `hiddenClassValue` as simple string default "hidden")
- Remove `transitionEnabled`, `toggleTransition`, `leave` state tracking
- Remove `logFallback()`, `_fallbackLogged` flag
- Keep only: `toggle()` toggles `this.menuTarget.classList.toggle(this.hiddenClassValue)`, `hide(event)` adds hidden class if click is outside controller element
- `hide(event)` must check `!this.element.contains(event.target)` to scope to own controller instance (V7 fix)
- `connect()` and `disconnect()` manage click-outside listener on document (not window) for proper cleanup
- Target: ~40 lines

### Task 2: Clean up notification_controller.js globals

Modify `app/assets/javascripts/source_monitor/controllers/notification_controller.js`:
- Remove `window.SourceMonitorControllers = window.SourceMonitorControllers || {}` and `window.SourceMonitorControllers.notification = this`
- If other code relies on global access to notification controller, replace with Stimulus `dispatch` events pattern:
  - Controller dispatches `notification:show` custom event on `this.element`
  - Callers use `this.dispatch("show", { detail: { message: "..." } })` pattern
- Check if any JS files reference `window.SourceMonitorControllers` -- if so, update those references

### Task 3: Clean up application.js globals

Modify `app/assets/javascripts/source_monitor/application.js`:
- Remove or guard `window.SourceMonitorStimulus = application` with environment check
- Option: wrap in `if (process.env.NODE_ENV !== "production")` or simply remove it (the Stimulus application is accessible via `Application.start()` return value if needed for debugging)
- Keep `window.Turbo.StreamActions.redirect` as-is (standard Turbo extension pattern, acceptable)

### Task 4: Update dropdown HTML for state isolation

Modify `app/views/source_monitor/sources/_row.html.erb`:
- Change `click@window->dropdown#hide` to `click@document->dropdown#hide` (if keeping declarative) OR rely on the new `connect()` listener in the controller
- Add `data-testid="source-actions-<%= dom_id(source) %>"` to each dropdown container for testing

Modify `app/views/source_monitor/sources/_health_status_badge.html.erb`:
- Same changes: ensure dropdown hide is scoped, add unique `data-testid`

### Task 5: Verify

- `yarn build` -- succeeds with no ESLint errors
- Rebuild JS assets: check `app/assets/builds/source_monitor/application.js` is updated
- `bin/rails test` -- full suite passes (no system test regressions)
- Verify no remaining `window.SourceMonitorControllers` references: `grep -r "SourceMonitorControllers" app/assets/`
- Verify no remaining stimulus-use references: `grep -r "stimulus-use\|useTransition\|transitionModule" app/assets/`
