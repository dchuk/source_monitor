---
phase: 4
plan: 1
title: UI Quick Fixes
wave: 1
depends_on: []
must_haves:
  - OPML import completes without spurious warning dialog
  - Toast notifications appear below nav header
  - Dashboard fetch schedule tables have aligned columns
---

# Plan 1: UI Quick Fixes

Three independent UI fixes: OPML import warning, toast positioning, and dashboard table alignment.

## Tasks

### Task 1: Fix OPML import navigation warning on completion

**Files:** `app/views/source_monitor/import_sessions/steps/_confirm.html.erb`

Add `data: { action: "submit->confirm-navigation#disable" }` to the Start Import form (line 113-115) so the confirm-navigation controller's guards are removed before the form submits and the Turbo Stream redirect fires.

The form currently:
```erb
<%= form_with model: import_session,
      url: source_monitor.step_import_session_path(import_session, step: "confirm"),
      method: :patch do |form| %>
```

Change to:
```erb
<%= form_with model: import_session,
      url: source_monitor.step_import_session_path(import_session, step: "confirm"),
      method: :patch,
      data: { action: "submit->confirm-navigation#disable" } do |form| %>
```

### Task 2: Push toast notification container below nav header

**Files:** `app/views/layouts/source_monitor/application.html.erb`

Change `top-4` to `top-16` on line 16:
```html
<div class="pointer-events-none fixed inset-x-0 top-16 z-50 flex justify-end px-6"
```

This pushes the notification container from 16px to 64px from the top, clearing the nav header.

### Task 3: Fix dashboard fetch schedule table column alignment

**Files:** `app/views/source_monitor/dashboard/_fetch_schedule.html.erb`

Add `table-fixed` to the table class and explicit widths to all `<th>` elements:
- Source: `w-[45%]`
- Status: `w-[15%]`
- Next Fetch: `w-[22%]`
- Interval: `w-[18%]`

Change:
```html
<table class="min-w-full divide-y divide-slate-200 text-left text-sm">
```
To:
```html
<table class="min-w-full table-fixed divide-y divide-slate-200 text-left text-sm">
```

And update all `<th>` elements with explicit widths.

### Task 4: Add/update tests

- Test that the import confirm form includes the disable action data attribute
- Verify system tests for dashboard still pass with table-fixed layout
- Run existing import session and dashboard tests to verify no regressions

## Acceptance Criteria

- [ ] Clicking "Start import" on OPML confirm step does NOT trigger beforeunload/turbo warning
- [ ] Toast notifications render below the nav header (top-16 = 64px)
- [ ] All dashboard fetch schedule tables have consistent column widths
- [ ] All existing tests pass
- [ ] RuboCop zero offenses
