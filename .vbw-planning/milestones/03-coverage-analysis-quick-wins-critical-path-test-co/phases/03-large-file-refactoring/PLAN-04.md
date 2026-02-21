---
phase: 3
plan: 4
title: fix-log-entry-and-autoloading
wave: 2
depends_on: [1, 2, 3]
skills_used: []
must_haves:
  truths:
    - "Running `grep 'self.table_name' app/models/source_monitor/log_entry.rb` returns no matches (hard-coded table name removed)"
    - "Running `grep 'ModelExtensions.register' app/models/source_monitor/log_entry.rb` shows the register call is present"
    - "Running `bin/rails test test/models/source_monitor/log_entry_test.rb` exits 0 with zero failures"
    - "Running `grep -c '^require ' lib/source_monitor.rb` shows fewer than 15 require statements (down from 66)"
    - "Running `bin/rails test` exits 0 with no regressions (760+ runs, 0 failures)"
    - "Running `bin/rubocop lib/source_monitor.rb app/models/source_monitor/log_entry.rb` exits 0"
  artifacts:
    - "app/models/source_monitor/log_entry.rb -- hard-coded table_name removed, uses ModelExtensions.register"
    - "lib/source_monitor.rb -- eager requires replaced with autoload declarations or Zeitwerk-compatible structure"
  key_links:
    - "REQ-11 satisfied -- LogEntry uses configurable table name prefix"
    - "REQ-12 satisfied -- eager requires replaced with autoloading"
---

# Plan 04: fix-log-entry-and-autoloading

## Objective

Address two remaining Phase 3 requirements: (1) Fix the LogEntry model's hard-coded `self.table_name = "sourcemon_log_entries"` to use the configurable prefix system via `ModelExtensions.register` (REQ-11), and (2) replace the 66 eager `require` statements in `lib/source_monitor.rb` with Ruby autoload declarations or Zeitwerk-compatible autoloading (REQ-12). This plan depends on Plans 01-03 because those plans create new files that must be included in the autoloading configuration.

## Context

<context>
@app/models/source_monitor/log_entry.rb -- 57 lines. Line 5 has `self.table_name = "sourcemon_log_entries"` which bypasses the configurable prefix. Line 17 already has `SourceMonitor::ModelExtensions.register(self, :log_entry)` which SHOULD set the table name dynamically. The bug is that `self.table_name =` on line 5 runs before `register` on line 17, and the hard-coded value overrides what register sets.
@lib/source_monitor/model_extensions.rb -- 110 lines. The `register` method calls `assign_table_name` which sets `model_class.table_name = "#{SourceMonitor.table_name_prefix}#{entry.base_table}"`. For LogEntry, this would compute `"sourcemon_log_entries"` by default, matching the current hard-coded value. The fix is to remove the hard-coded line and let register handle it.
@app/models/source_monitor/source.rb -- line 53: `SourceMonitor::ModelExtensions.register(self, :source)` -- no hard-coded table_name. This is the correct pattern.
@app/models/source_monitor/item.rb -- line 34: same pattern, no hard-coded table_name.
@test/models/source_monitor/log_entry_test.rb -- existing tests for LogEntry model.

@lib/source_monitor.rb -- 171 lines. Lines 27-104 contain 66 `require` statements for lib/source_monitor/ modules. Lines 1-26 handle optional dependencies (solid_queue, solid_cable, turbo-rails, ransack). Lines 106-170 define the SourceMonitor module methods.
@lib/source_monitor/engine.rb -- 110 lines. The engine class with initializers. Already uses `require` for a few things inline.

**Decomposition rationale:** These are two small, focused changes that don't warrant separate plans. The LogEntry fix is a 1-line removal. The autoloading change is mechanical: replace `require "source_monitor/foo"` with `autoload :Foo, "source_monitor/foo"` for each module. Both changes have clear verification criteria.

**Trade-offs considered:**
- **Zeitwerk vs Ruby autoload:** Rails engines already use Zeitwerk for app/ directory (models, controllers, etc). For lib/ code, the common patterns are: (a) Zeitwerk push_dir in engine.rb, (b) Ruby `autoload`, or (c) keep requires. Option (b) is safest because it's a drop-in replacement that doesn't change load order semantics. Option (a) would require restructuring some files. Going with (b) -- Ruby autoload -- because it's the least disruptive.
- **Keep optional dependency handling:** The `begin; require "solid_queue"; rescue LoadError; end` blocks at the top of source_monitor.rb are for external gems and must stay as-is. Only the internal `require "source_monitor/..."` lines are candidates for autoload.
- **Autoload scope:** Only convert requires for classes/modules that are defined under the `SourceMonitor` namespace. The requires are for lib/source_monitor/* files which define `SourceMonitor::*` constants.
- **LogEntry table_name:** Simply removing line 5 (`self.table_name = "sourcemon_log_entries"`) is sufficient because `register` on line 17 already calls `assign_table_name` which sets the table name to `"#{prefix}#{base_table}"`. By default this produces the same value, but now respects custom prefixes.

**What constrains the structure:**
- The `autoload` statements must be inside the `SourceMonitor` module block
- Some modules are nested (e.g., `SourceMonitor::Fetching::FeedFetcher`) -- autoload only the top-level namespace module (`Fetching`), and let the sub-module's file handle its own autoloads
- Engine initializers expect certain constants to be available -- autoload ensures they load on first reference
- The 4 optional dependency requires (solid_queue, solid_cable, turbo-rails, ransack) stay as-is
- The `version.rb` require stays explicit (needed before engine loads)
- The `engine.rb` require stays explicit (needed for Rails::Engine registration)
- The `configuration.rb` require stays explicit (needed by SourceMonitor.config)
- The `model_extensions.rb` require stays explicit (needed by models at class load time)
</context>

## Tasks

### Task 1: Fix LogEntry hard-coded table name

- **name:** fix-log-entry-table-name
- **files:**
  - `app/models/source_monitor/log_entry.rb`
- **action:** Remove line 5 (`self.table_name = "sourcemon_log_entries"`). The `ModelExtensions.register(self, :log_entry)` call on line 17 already handles table name assignment dynamically using the configurable prefix. Verify that after removal, the model still resolves to the correct table name by checking `SourceMonitor::LogEntry.table_name` in a test or rails console context.
- **verify:** `grep 'self.table_name' app/models/source_monitor/log_entry.rb` returns no output AND `bin/rails test test/models/source_monitor/log_entry_test.rb` exits 0 AND `bin/rails test` exits 0
- **done:** Hard-coded table name removed. LogEntry uses configurable prefix system. REQ-11 satisfied.

### Task 2: Replace eager requires with autoload declarations

- **name:** replace-requires-with-autoload
- **files:**
  - `lib/source_monitor.rb`
- **action:** Replace the 66 `require "source_monitor/..."` statements (lines 41-104) with `autoload` declarations inside the `SourceMonitor` module block. Group autoloads by domain:

  Keep as explicit requires (before autoloads):
  - `require "source_monitor/version"` -- needed for VERSION constant
  - `require "active_support/core_ext/module/redefine_method"` -- needed for table_name_prefix setup
  - `require "source_monitor/engine"` -- needed for Rails::Engine registration
  - `require "source_monitor/configuration"` -- needed by SourceMonitor.config (called early)
  - `require "source_monitor/model_extensions"` -- needed by model class bodies at load time
  - `require "source_monitor/events"` -- needed by config.events callbacks
  - `require "source_monitor/instrumentation"` -- needed by engine initializer (Metrics.setup_subscribers!)
  - `require "source_monitor/metrics"` -- needed by engine initializer
  - `require "source_monitor/health"` -- needed by engine initializer (Health.setup!)
  - `require "source_monitor/realtime"` -- needed by engine initializer (Realtime.setup!)

  Convert to autoload:
  ```ruby
  autoload :HTTP, "source_monitor/http"
  autoload :FeedjiraExtensions, "source_monitor/feedjira_extensions"
  autoload :Scheduler, "source_monitor/scheduler"
  autoload :Assets, "source_monitor/assets"

  module Dashboard
    autoload :QuickAction, "source_monitor/dashboard/quick_action"
    autoload :RecentActivity, "source_monitor/dashboard/recent_activity"
    autoload :RecentActivityPresenter, "source_monitor/dashboard/recent_activity_presenter"
    autoload :QuickActionsPresenter, "source_monitor/dashboard/quick_actions_presenter"
    autoload :Queries, "source_monitor/dashboard/queries"
    autoload :TurboBroadcaster, "source_monitor/dashboard/turbo_broadcaster"
    autoload :UpcomingFetchSchedule, "source_monitor/dashboard/upcoming_fetch_schedule"
  end
  ```
  And similarly for Logs, Analytics, Jobs, Security, Pagination, TurboStreams, Scrapers, Scraping, Fetching, Items, Health (sub-modules), Setup, Sources, Release modules.

  For nested modules like `Fetching::FeedFetcher`, use:
  ```ruby
  module Fetching
    autoload :FetchError, "source_monitor/fetching/fetch_error"
    autoload :FeedFetcher, "source_monitor/fetching/feed_fetcher"
    autoload :FetchRunner, "source_monitor/fetching/fetch_runner"
    autoload :RetryPolicy, "source_monitor/fetching/retry_policy"
    autoload :StalledFetchReconciler, "source_monitor/fetching/stalled_fetch_reconciler"
  end
  ```

  IMPORTANT: Some modules are referenced in engine initializers that run at boot. The explicit requires above ensure those are loaded. All other modules will be loaded on first reference via autoload.
- **verify:** `grep -c '^require ' lib/source_monitor.rb` shows fewer than 15 AND `grep -c 'autoload' lib/source_monitor.rb` shows at least 40 AND `bin/rails test` exits 0 with 760+ runs
- **done:** Eager requires replaced with autoload. Module loading is lazy for non-boot-critical code.

### Task 3: Verify full integration and RuboCop

- **name:** verify-autoload-integration
- **files:**
  - `lib/source_monitor.rb`
  - `app/models/source_monitor/log_entry.rb`
- **action:** Run the full test suite to verify no load-order issues from the autoload conversion. Run RuboCop on the modified files. Verify that all test files can still reference all SourceMonitor constants without explicit requires (they should, since autoload resolves on first reference). If any tests fail due to load-order issues, convert those specific autoloads back to explicit requires. Document any such cases.
- **verify:** `bin/rails test` exits 0 with 760+ runs AND `bin/rubocop lib/source_monitor.rb app/models/source_monitor/log_entry.rb` exits 0
- **done:** Full integration verified. No load-order regressions. RuboCop clean. REQ-11 and REQ-12 satisfied.

## Verification

1. `grep 'self.table_name' app/models/source_monitor/log_entry.rb` returns no output
2. `grep -c '^require ' lib/source_monitor.rb` shows fewer than 15
3. `grep -c 'autoload' lib/source_monitor.rb` shows at least 40
4. `bin/rails test` exits 0 (no regressions, 760+ runs)
5. `bin/rubocop lib/source_monitor.rb app/models/source_monitor/log_entry.rb` exits 0

## Success Criteria

- [ ] LogEntry no longer has hard-coded table name
- [ ] LogEntry uses ModelExtensions.register for dynamic table name (already present)
- [ ] Eager require count in lib/source_monitor.rb reduced from 66 to fewer than 15
- [ ] At least 40 autoload declarations replace the eager requires
- [ ] All existing tests pass without modification
- [ ] Full test suite passes (760+ runs, 0 failures)
- [ ] RuboCop passes on modified files
- [ ] REQ-11 and REQ-12 satisfied
