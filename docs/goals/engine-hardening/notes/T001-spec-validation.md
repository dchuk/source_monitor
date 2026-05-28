# T001 — Judge spec validation (full receipt)

Decision: **approved_with_notes** · go for T002 · full_outcome_complete: false · sequence #131 -> #130 -> #129 OK · parallel NOT allowed (T003 & T004 share application_controller.rb; safe only serially).

## Per-issue

### #131 (packaging) — spec_valid: true, no material drift
- `source_monitor.gemspec:25-31` reject list omits `.claude/`; line 30 `Dir[".claude/skills/sm-*/**/*"]` re-adds 39 sm-* files.
- Currently **64 non-sm `.claude` files ship** (agents/commands/hooks/agent-memory + ~17 non-sm skills).
- Adding `.claude/` to reject list is correct + sufficient.
- `test/integration/release_packaging_test.rb:65` already runs `gem build source_monitor.gemspec`, proving gemspec loads from repo root → new `test/gemspec_packaging_test.rb` is safe.

### #130 (notifications) — spec_valid: true, with drift
- **DRIFT:** spec said "no broadcaster test file"; `test/lib/source_monitor/realtime/broadcaster_test.rb` ALREADY EXISTS (19KB), already stubs `Turbo::StreamsChannel.broadcast_append_to` and tests `broadcast_toast` (lines 151-189). Worker **extends**, not creates.
- Both leak paths confirmed: (a) `application_controller.rb:63-79` `broadcast_flash_toasts` after_action → `Realtime.broadcast_toast` per flash; (b) `broadcaster.rb:66-85` `broadcast_toast` → `NOTIFICATION_STREAM = "source_monitor_notifications"`.
- Layout subscribes globally: `application.html.erb:15`. `StreamResponder#toast` (`stream_responder.rb:43-54`) is response-local (good).
- **Two extra background `broadcast_toast` call sites the spec missed:** `lib/source_monitor/health/source_health_check_orchestrator.rb:57` and `lib/source_monitor/fetching/feed_fetcher/source_updater.rb:196` (auto-pause). Both source-operational → fit the "keep global, context-free" default; Worker should be aware.

### #129 (auth) — spec_valid: true, with critical drift
- **DRIFT (critical):** dummy-initializer-only opt-in does NOT keep suite green. `test/test_helper.rb:85-89` calls `SourceMonitor.reset_configuration!` in EVERY test setup (rebuilds `Configuration.new` at `lib/source_monitor.rb:236`), wiping the dummy initializer's `open_access` per-test. `test/test_helper.rb` was NOT in #129's named files.
- Silent no-op confirmed: `authentication.rb:42-46` `call_handler` returns early when handler nil. before_actions `application_controller.rb:7-8`. `authentication_settings.rb:39-44` `reset!` present (add `open_access` reset there).
- ~24 of 26 controller/integration test files hit real engine routes with NO handler and expect 200 → all 403 under fail-closed unless the shared harness opts in.
- Must flip `test/controllers/source_monitor/application_controller_test.rb:28-31` ("skips authentication when host has not configured it" asserts `:success`) → assert `:forbidden`.

Tests relying on implicit open access (must be handled via test_helper open_access enablement):
sources, dashboard, items, source_fetches, health, bulk_scrape_enablements, fetch_logs, item_scrapes, logs, scrape_logs, source_bulk_scrapes, source_favicon_fetches, source_health_checks, source_health_resets, source_retries, source_scrape_tests, sources_favicon, sources_sort controllers; integration: engine_mounting, navigation, favicon_integration.

## Required board updates (PM applied)
1. T004 allowed_files += `test/test_helper.rb` (enable open_access in per-test setup). **Most important** — without it the suite can't pass.
2. T004 must flip `application_controller_test.rb:28-31` → `:forbidden`.
3. T003: extend existing `broadcaster_test.rb`; aware of the two extra background toast sites.
4. T003 & T004 serial-only (shared application_controller.rb).

## Owner questions (all non-blocking, workable defaults)
- #130: keep background toasts global+context-free (default) vs remove entirely.
- #129: opt-in name `open_access` (default, adjustable).
- #129: enable open_access in test_helper (default, lowest churn) vs per-file configure_authentication.
