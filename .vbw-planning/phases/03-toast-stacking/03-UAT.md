---
phase: 3
plan_count: 1
status: complete
completed: 2026-02-21
started: 2026-02-20
total_tests: 3
passed: 3
skipped: 0
issues: 0
---

# Phase 3: Toast Stacking -- UAT

## P01-T1: Toast overflow capping and badge

**Plan:** 01 -- Toast Stacking: Container Controller, Templates, and Integration

**Scenario:** Navigate to http://localhost:3000/source_monitor/sources. Trigger 5+ toast notifications rapidly (e.g., fetch multiple sources, or use browser console to inject toasts). Verify that only 3 toasts are visible at a time, and a "+N more" badge appears below the stack showing the overflow count.

**Expected:** Max 3 toasts visible. Badge shows "+2 more" (or correct count). Hidden toasts are not visible or interactable.

**Result:** PASS

---

## P01-T2: Expand/collapse and clear all

**Plan:** 01 -- Toast Stacking: Container Controller, Templates, and Integration

**Scenario:** With 4+ toasts active (some hidden behind the badge), click the "+N more" badge. Verify all hidden toasts slide into view. Click outside the toast area or click the badge again to collapse. Then expand again and click "Clear all" -- verify all toasts are dismissed at once.

**Expected:** Click badge expands stack showing all toasts. Click outside or badge again collapses. "Clear all" removes every toast and the badge disappears.

**Result:** PASS

---

## P01-T3: Toast auto-dismiss and promote-on-dismiss

**Plan:** 01 -- Toast Stacking: Container Controller, Templates, and Integration

**Scenario:** Trigger 5+ toasts. Wait for the visible toasts to auto-dismiss (5s each). Watch as hidden toasts are promoted into the visible slots. Verify the badge count decrements as toasts are dismissed. If possible, trigger an error toast and confirm it persists longer (~10s) than info/success toasts (~5s).

**Expected:** Toasts auto-dismiss after their delay. Hidden toasts slide into view as visible ones dismiss. Badge count decrements. Error toasts last ~10s vs ~5s for others.

**Result:** PASS
