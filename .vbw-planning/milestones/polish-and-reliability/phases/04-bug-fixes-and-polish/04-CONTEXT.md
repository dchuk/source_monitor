# Phase 4 Context: Bug Fixes & Polish

## Decisions

### BF-01: OPML Import Warning
- **Fix:** Add `data-action="submit->confirm-navigation#disable"` to the Start Import form in `steps/_confirm.html.erb` (line 113)
- **Approach:** Disable navigation guard on form submit, before the Turbo Stream redirect fires
- **No ambiguity:** Straightforward Stimulus action binding

### BF-02: Toast Notification Positioning
- **Fix:** Change `top-4` to `top-16` (64px) in `application.html.erb` line 16
- **Decision:** Right below the header, no gap. Clean and tight.
- **File:** `app/views/layouts/source_monitor/application.html.erb`

### BF-03: Dashboard Table Column Alignment
- **Fix:** Apply `table-fixed` with explicit column widths: Source ~45%, Status ~15%, Next Fetch ~22%, Interval ~18%
- **Approach:** Keep separate card/table structure per time bracket; just ensure consistent column widths
- **File:** `app/views/source_monitor/dashboard/_fetch_schedule.html.erb`

### BF-04: Delete Sources 500 Error
- **Approach:** Investigate root cause, then fix
- **Key insight from user:** The error happens in a host app that extends SourceMonitor::Source and SourceMonitor::Item with its own models that reference these engine models
- **Likely cause:** Host app FK constraints on engine models aren't covered by `dependent: :destroy`. When engine deletes a source, cascading deletes on items/logs hit FK violations from host-app-added references.
- **Engine design consideration:** The engine should either:
  1. Use `dependent: :destroy` ordering that respects host-app extensions, OR
  2. Provide a hook for host apps to clean up their references before deletion, OR
  3. Handle FK violations gracefully with a useful error message about dependent records
- **Also investigate:** Active Storage favicon attachment and whether `has_one_attached` cascade is causing issues
- **Also add:** Error handling wrapper regardless, for defensive robustness

### BF-05: Published Column
- **Approach:** Investigate parser first before adding fallback
- **Current code:** `entry_parser.rb#extract_timestamp` looks for `published` then `updated` Feedjira methods
- **Investigation needed:**
  1. Check if Feedjira actually exposes `published` for RSS 2.0 `<pubDate>` entries
  2. Check if `published_at` is in the item_creator's allowed attributes and is actually being persisted
  3. Test with known feeds that have pubDate tags to see if the parser extracts them
- **If parser works:** The feeds genuinely lack dates -> add created_at fallback for display
- **If parser is broken:** Fix the timestamp extraction
