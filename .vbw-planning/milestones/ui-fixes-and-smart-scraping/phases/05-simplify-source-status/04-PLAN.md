---
phase: "05"
plan: "04"
title: "UI, Helper, and View Updates"
wave: 2
depends_on: ["01"]
must_haves:
  - "Health badge helper maps 4 statuses: working=green, declining=yellow, improving=blue, failing=red"
  - "Health filter dropdown shows Working, Declining, Improving, Failing"
  - "Interactive health actions updated for new status values"
  - "Dashboard health distribution uses new 4-status set"
---

# Plan 04: UI, Helper, and View Updates

## Goal
Update all UI components to reflect the new 4-status health model: badge colors, filter dropdowns, interactive actions, and dashboard stats.

## Tasks

### Task 1: Update HealthBadgeHelper
**Files:** `app/helpers/source_monitor/health_badge_helper.rb`

Replace the 7-status mapping with 4 statuses:
- `"working"` -> `{ label: "Working", classes: "bg-green-100 text-green-700" }`
- `"declining"` -> `{ label: "Declining", classes: "bg-yellow-100 text-yellow-700" }`
- `"improving"` -> `{ label: "Improving", classes: "bg-sky-100 text-sky-700" }`
- `"failing"` -> `{ label: "Failing", classes: "bg-rose-100 text-rose-700" }`

Update `source_health_actions`:
- Change `when "critical", "declining"` to `when "failing", "declining"`
- Remove the `when "auto_paused"` case (auto-pause is now operational, not a health status)
- Add a new case for `when "failing"` that includes the reset action alongside fetch/health check

Update `interactive_health_status?`:
- Change `%w[critical declining auto_paused]` to `%w[failing declining]`

Update the default fallback from `"healthy"` to `"working"`.

### Task 2: Update sources index health filter dropdown
**Files:** `app/views/source_monitor/sources/index.html.erb`

Change the health filter options from:
```
["All Health", ""], ["Healthy", "healthy"], ["Warning", "warning"], ["Declining", "declining"], ["Critical", "critical"]
```
To:
```
["All Health", ""], ["Working", "working"], ["Declining", "declining"], ["Improving", "improving"], ["Failing", "failing"]
```

### Task 3: Update dashboard health distribution
**Files:** `app/views/source_monitor/dashboard/_stats.html.erb`, `lib/source_monitor/dashboard/queries/stats_query.rb`

In `_stats.html.erb`, update the `health_colors` mapping:
- Replace `"healthy"` with `"working"`, keep green
- Replace `"warning"` with `"improving"`, use sky/blue
- Keep `"declining"` with orange/yellow
- Replace `"critical"` with `"failing"`, keep rose/red

In `stats_query.rb`, update the `health_distribution` method:
- Change `%w[healthy warning declining critical]` to `%w[working declining improving failing]`

### Task 4: Update source row partial default fallback
**Files:** `app/views/source_monitor/sources/_row.html.erb`

No changes needed -- the row partial delegates to `source_health_badge` which is updated in Task 1. However, verify there are no hardcoded status string references in the row partial.
