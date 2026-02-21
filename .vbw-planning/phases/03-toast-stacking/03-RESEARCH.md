# Phase 3: Toast Stacking -- Research

## Findings

### Stimulus + MutationObserver Pattern
- `stimulus-use` library provides `useMutation` composable for detecting DOM changes
- Config: `childList: true`, `subtree: true` to observe child additions/removals
- Callback: `mutate(entries)` receives MutationRecord objects
- Both Turbo Stream inline responses and ActionCable broadcasts trigger mutations uniformly

### Overflow Capping Logic
- Store max visible as a Stimulus value (default: 3)
- On mutation: iterate toast elements, show top N, hide rest
- Use `visibility: hidden` + `opacity: 0` (not `display: none`) to preserve layout and enable transitions
- Track hidden count for overflow badge

### CSS Animation for Slide Reveal
- Use `max-height` transition for expand/collapse of overflow section
- Calculate actual `scrollHeight` on expand (avoid magic numbers)
- On `transitionend`, set `max-height: auto` for dynamic content
- Consider `ResizeObserver` as alternative to manual height calculation

### Click-Outside Pattern
- `stimulus-use` provides `useClickOutside` mixin
- Dispatches `click:outside` event for clicks outside controller element
- Only activate when overflow is expanded

### Promote-on-Dismiss Pattern
- Individual toast dispatches custom `toast:dismissed` event on removal
- Container listens for events, calls `recalculateVisibility()`
- Flex column handles re-flow automatically when hidden toast becomes visible

### Controller Architecture Split
- `notification_controller.js` (existing): per-toast lifecycle only
- `notification_container_controller.js` (new): overflow state, capping, expand/collapse, clear-all
- Communication via MutationObserver + custom events

## Relevant Patterns

### From stimulus-components/stimulus-notification
- `data-notification-delay-value` for auto-dismiss timing
- Transitions via data attributes (`data-transition-enter-from`)
- Individual notification management; stacking left to consumer

### From stimulus-use ecosystem
- `useMutation`: observe child additions/removals
- `useClickOutside`: click-outside-to-collapse
- Debounce pattern with `requestAnimationFrame`

## Risks

1. **MutationObserver performance**: Rapid appends can fire hundreds of mutations. Mitigation: debounce with `requestAnimationFrame`
2. **Height calculation**: Avoid magic `max-height` values. Use `scrollHeight` or `ResizeObserver`
3. **Target scoping**: Use distinct target names between container and individual toast controllers
4. **Keyboard accessibility**: Hidden toasts need `aria-hidden="true"` and `inert` attribute
5. **Race condition**: Toast dismissed during expand animation invalidates height. Debounce recalculation
6. **CSS transition jank**: Rapid append/remove queues animations. Use short durations (~150-200ms)

## Recommendations

1. Create `notification_container_controller.js` with MutationObserver (no stimulus-use dependency needed -- native MutationObserver is simple enough)
2. Keep existing `notification_controller.js` unchanged, add custom event dispatch on dismiss
3. Use CSS `max-height` + `overflow: hidden` transitions for expand/collapse
4. Debounce `recalculateVisibility()` via `requestAnimationFrame`
5. Add `aria-hidden` and `inert` to hidden toasts for accessibility
6. Add ARIA live region for overflow count announcements
