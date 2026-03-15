---
phase: "05"
plan: "01"
title: "SourceDetailsPresenter Extraction"
wave: 1
depends_on: []
skills_used:
  - rails-presenter
  - tdd-cycle
  - sm-domain-model
must_haves:
  - "New SourceMonitor::SourceDetailsPresenter at app/presenters/source_monitor/source_details_presenter.rb extending BasePresenter (SimpleDelegator)"
  - "SourceDetailsPresenter has methods: fetch_interval_display, circuit_state_label, adaptive_interval_label, details_hash, formatted_next_fetch_at, formatted_last_fetched_at"
  - "SourceDetailsPresenter test at test/presenters/source_monitor/source_details_presenter_test.rb with tests for each public method"
  - "app/views/source_monitor/sources/_details.html.erb wraps local source variable in SourceDetailsPresenter and uses presenter methods instead of inline hash building and number_with_precision calls"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 01: SourceDetailsPresenter Extraction

## Objective

Extract ~50 lines of inline view logic from `_details.html.erb` (362 lines) into a `SourceDetailsPresenter` (V14). The template currently builds hashes with conditional formatting, number_with_precision calls, date formatting, and ternary operators -- all of which belong in a presenter.

## Context

- @.claude/skills/rails-presenter/SKILL.md -- Presenter patterns with BasePresenter (SimpleDelegator)
- @.claude/skills/tdd-cycle/SKILL.md -- TDD red-green-refactor workflow
- @.claude/skills/sm-domain-model/SKILL.md -- Source model details (fetch_interval_minutes, fetch_circuit_open?, adaptive_fetching_enabled?)
- `app/views/source_monitor/sources/_details.html.erb` (362 lines) -- largest partial, contains inline formatting logic (lines 177-230)
- No existing BasePresenter in the engine -- check if one exists; if not, create one following the rails-presenter skill pattern
- **Important:** Do NOT modify `sources_controller.rb` -- instantiate the presenter inside `_details.html.erb` partial to avoid file conflicts with Plan 02 which modifies the controller's index action

## Tasks

### Task 1: Create BasePresenter if missing and write SourceDetailsPresenter tests (TDD red)

Check if `app/presenters/source_monitor/base_presenter.rb` exists. If not, create it (SimpleDelegator with ActionView helper includes).

Create `test/presenters/source_monitor/source_details_presenter_test.rb`:
- Test `fetch_interval_display` returns formatted string like "30 minutes (~0.50 hours)"
- Test `circuit_state_label` returns "Closed" when circuit not open, "Open until {date}" when open
- Test `adaptive_interval_label` returns "Auto" or "Fixed"
- Test `details_hash` returns a Hash with expected keys (Website, Fetch interval, Adaptive interval, Scraper, etc.)
- Test `formatted_next_fetch_at` handles nil and present timestamps
- Test `formatted_last_fetched_at` handles nil and present timestamps
- Test delegation to underlying Source model (name, feed_url, etc.)
- Use `create_source!` factory from existing test helpers

### Task 2: Implement SourceDetailsPresenter

Create `app/presenters/source_monitor/source_details_presenter.rb`:
- Class `SourceMonitor::SourceDetailsPresenter < SourceMonitor::BasePresenter`
- Extract from `_details.html.erb` lines 177-230: `fetch_interval_display`, `circuit_state_label`, `adaptive_interval_label`
- `details_hash` method that builds the hash currently inlined in the template
- Date formatting helpers for fetch timestamps
- All formatting methods that currently use `number_with_precision`, conditional ternaries, and `strftime`

### Task 3: Update template to use presenter

Modify `app/views/source_monitor/sources/_details.html.erb`:
- At the top of the partial, wrap the source local in the presenter: `<% presenter = SourceMonitor::SourceDetailsPresenter.new(source) %>`
- Replace inline hash building (lines 177-230) with `presenter.details_hash` calls
- Replace `number_with_precision(source.fetch_interval_minutes / 60.0, ...)` with `presenter.fetch_interval_display`
- Replace circuit state conditional logic with `presenter.circuit_state_label`
- Keep all HTML structure unchanged -- only swap logic calls
- Do NOT modify `sources_controller.rb` (Plan 02 modifies it for index action)

### Task 4: Verify

- `bin/rails test test/presenters/source_monitor/source_details_presenter_test.rb` -- all pass
- `bin/rails test test/controllers/source_monitor/sources_controller_test.rb` -- all pass
- `bin/rails test` -- full suite passes
- `bin/rubocop` -- zero offenses
