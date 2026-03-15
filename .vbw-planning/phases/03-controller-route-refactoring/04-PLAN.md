---
phase: "03"
plan: "04"
title: "Decouple Pluralizer from SourceTurboResponses"
wave: 1
depends_on: []
must_haves:
  - "BulkResultPresenter no longer requires pluralizer injection -- uses ActionController::Base.helpers.pluralize directly or includes ActiveSupport::Inflector"
  - "SourceTurboResponses#bulk_scrape_flash_payload no longer creates/passes pluralizer lambda"
  - "Existing bulk scrape controller tests still pass"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 04: Decouple Pluralizer from SourceTurboResponses

## Objective

Remove the awkward pluralizer lambda injection from SourceTurboResponses into BulkResultPresenter (C7), letting the presenter handle pluralization directly.

## Context

- `app/controllers/source_monitor/source_turbo_responses.rb:109-113` creates a lambda wrapping `ActionController::Base.helpers.pluralize` and injects it into BulkResultPresenter
- `lib/source_monitor/scraping/bulk_result_presenter.rb` uses the injected `pluralizer` callable throughout
- The presenter is a plain Ruby object that shouldn't need controller-layer dependencies injected
- `ActionController::Base.helpers.pluralize` is available anywhere in Rails -- or simpler, use `String#pluralize` from ActiveSupport + count interpolation

## Tasks

### Task 1: Update BulkResultPresenter to self-pluralize

In `lib/source_monitor/scraping/bulk_result_presenter.rb`:
- Remove `pluralizer` from `initialize` parameters and `attr_reader`
- Replace all `pluralizer.call(count, word)` calls with a private `pluralize(count, word)` method that uses `"#{count} #{count == 1 ? word : word.pluralize}"`
- This avoids any dependency on ActionController

### Task 2: Update SourceTurboResponses

In `app/controllers/source_monitor/source_turbo_responses.rb`:
- Simplify `bulk_scrape_flash_payload` to remove the pluralizer lambda
- Just call `BulkResultPresenter.new(result:)` without pluralizer

### Task 3: Update tests

Update any tests that construct BulkResultPresenter with a pluralizer argument to remove it. Check:
- `test/lib/source_monitor/scraping/bulk_result_presenter_test.rb` (if exists)
- `test/controllers/source_monitor/source_bulk_scrapes_controller_test.rb`

### Task 4: Verify

- `bin/rails test` -- all pass
- `bin/rubocop` -- zero offenses
