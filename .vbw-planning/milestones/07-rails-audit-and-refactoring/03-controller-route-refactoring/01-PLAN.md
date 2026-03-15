---
phase: "03"
plan: "01"
title: "Extract ItemScrapesController & Simplify Logging"
wave: 1
depends_on: []
must_haves:
  - "New ItemScrapesController with create action at POST /items/:id/scrape (singular resource)"
  - "Route changed from custom member action to nested singular resource"
  - "Scrape action code removed from ItemsController"
  - "ItemsController log_manual_scrape simplified: no defensive Rails.logger checks, no rescue StandardError"
  - "View partial items/_details.html.erb updated to use new route helper"
  - "New item_scrapes_controller_test.rb with tests for turbo_stream and html formats"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 01: Extract ItemScrapesController & Simplify Logging

## Objective

Extract the custom `scrape` action from ItemsController into a dedicated ItemScrapesController following CRUD conventions (C1), and simplify the over-defensive logging pattern (C8).

## Context

- `app/controllers/source_monitor/items_controller.rb` has a `scrape` action (lines 39-85) with a TODO comment acknowledging this debt
- Route is `post :scrape, on: :member` in routes.rb line 20 -- violates everything-is-CRUD convention
- `log_manual_scrape` (lines 109-116) has unnecessary `defined?(Rails)` checks and `rescue StandardError`
- View reference: `app/views/source_monitor/items/_details.html.erb:165` uses `scrape_item_path(item)`
- No existing scrape tests in items_controller_test.rb -- tests will be net-new

## Tasks

### Task 1: Write tests for ItemScrapesController (TDD red)

Create `test/controllers/source_monitor/item_scrapes_controller_test.rb` with:
- Test `create` enqueues scrape via turbo_stream format (mock Enqueuer)
- Test `create` with html format redirects to item path
- Test `create` when enqueue fails returns unprocessable_entity
- Test `create` when item already enqueued returns ok with notice

Use existing test patterns: `create_source!`, WebMock stubs, `fixtures :users`.

### Task 2: Create ItemScrapesController

Create `app/controllers/source_monitor/item_scrapes_controller.rb`:
- Class `ItemScrapesController < ApplicationController`
- `include ActionView::RecordIdentifier`
- `before_action :set_item`
- `create` action with the scrape logic extracted from ItemsController
- Move `scrape_flash_payload` as private method
- Simplified logging: just `Rails.logger.info(...)` without defensive checks or rescue

### Task 3: Update routes

In `config/routes.rb`, replace:
```ruby
resources :items, only: %i[index show] do
  post :scrape, on: :member
end
```
with:
```ruby
resources :items, only: %i[index show] do
  resource :scrape, only: :create, controller: "item_scrapes"
end
```

### Task 4: Update view and clean up ItemsController

- Update `app/views/source_monitor/items/_details.html.erb:165` to use the new route helper (`item_scrape_path(item)` instead of `scrape_item_path(item)`)
- Remove `scrape` action, `scrape_flash_payload`, and `log_manual_scrape` from ItemsController
- Remove `scrape` from `before_action :set_item, only: %i[show scrape]` (becomes `only: :show`)

### Task 5: Verify

- `bin/rails test` -- all pass
- `bin/rubocop` -- zero offenses
- Confirm route helper works: `bin/rails routes -g scrape` shows new path
