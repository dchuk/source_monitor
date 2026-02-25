# Phase 3: Toast Stacking -- Context

Gathered: 2026-02-20
Calibration: architect

## Phase Boundary
Replace uncapped toast notification stacking with a max-visible cap and "+N more" click-to-expand pattern for cleaner UX during bulk operations.

## Decisions

### Expand/Collapse Interaction
- Click/tap only (no hover) -- same behavior on all devices
- Click the "+N more" badge to expand, click again or outside to collapse
- Slide-down animation (~200ms) for hidden toasts appearing, matching existing dismiss transition

### Toast Priority When Capped
- Newest 3 always shown (simple FIFO ordering, no slot reservation)
- Error toasts get a longer auto-dismiss delay (e.g., 10s vs 5s for info) so they naturally persist longer
- No priority-based slot displacement logic

### Dismiss Behavior with Overflow
- Dismissing a visible toast promotes the next hidden toast into view (slide in)
- "+N more" count decrements as toasts are promoted or auto-dismissed
- "Clear all" link appears when overflow exists, dismisses everything at once

### Architecture: Client-Only
- All capping, overflow counting, expand/collapse, and dismiss-all lives in a new Stimulus controller
- New controller wraps `#source_monitor_notifications` container (not per-toast)
- Existing `notification_controller.js` stays as-is (per-toast auto-dismiss + close)
- Server continues appending toasts unchanged -- zero backend changes
- Both delivery paths (inline Turbo Stream + ActionCable broadcast) work unmodified

### Open (Claude's discretion)
- Max visible cap default: 3 (configurable via Stimulus value)
- Error toast delay: 10000ms vs default 5000ms for info/success/warning
- Collapse animation: reverse of expand (slide up ~200ms)
- Badge styling: small pill/chip matching existing toast color palette (slate)

## Deferred Ideas
None
