# Phase 02: Feed Reliability — Context

Gathered: 2026-03-05
Calibration: architect

## Phase Boundary
Fix fetch pipeline reliability issues: "No valid XML parser" errors for Cloudflare-challenged feeds, and ConcurrencyError (advisory lock busy) when force-fetching a source that's already locked.

## Decisions

### Cloudflare Bypass Strategy
- Light bypass approach: try common workarounds (different UA, cookie persistence, alternate endpoints) but no headless browser dependency
- When light bypass fails: show "Cloudflare Blocked" status badge on the source, detailed error in fetch logs
- User stays in control — no automatic actions on CF-blocked sources (beyond auto-pause threshold)

### Force-Fetch Lock Contention
- Force-fetch hitting an advisory lock: skip immediately with "Fetch already in progress" message, don't queue another
- Scoped to force-fetch only: scheduled fetches keep existing retry logic (4 retries)
- No stacking of jobs — fail fast and let user retry manually

### Error Categorization
- Structured + coarse: coarse category for filtering (Network, Parse, Blocked, Auth, Unknown), plus raw error details (HTTP status, response snippet) in a detail field
- HTML response detection: sniff response body to distinguish Cloudflare/login wall (Blocked category) from actually malformed XML (Parse Error)
- Different root causes get different categories even when the symptom is the same ("can't parse")

### Auto-Pause Policy
- Auto-pause after 5 consecutive failures of any error category
- Applies uniformly across all error types (not just persistent ones)
- User gets notified when auto-pause triggers
- Integrates with existing health status system

### Open (Claude's discretion)
- Specific light bypass techniques to try (UA rotation, cookie jars, conditional GET headers)
- Exact coarse error category taxonomy (can refine during implementation)
- Notification mechanism for auto-pause (toast, log entry, or both)

## Deferred Ideas
None
