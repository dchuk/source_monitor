# Routes Refactoring Evaluation - Phase 20.03.03

**Date:** 2025-10-14
**Task:** Evaluate refactoring non-RESTful custom member actions to nested resource controllers

## Current Implementation

```ruby
resources :sources do
  post :fetch, on: :member
  post :retry, on: :member
  post :scrape_all, on: :member
end
```

This creates:

- `POST /sources/:id/fetch` → `SourcesController#fetch`
- `POST /sources/:id/retry` → `SourcesController#retry`
- `POST /sources/:id/scrape_all` → `SourcesController#scrape_all`

## Proposed RESTful Alternative

Create three nested resource controllers:

```ruby
resources :sources do
  resource :fetch, only: [:create], controller: 'source_fetches'
  resource :retry, only: [:create], controller: 'source_retries'
  resource :bulk_scrape, only: [:create], controller: 'source_bulk_scrapes'
end
```

This would create:

- `POST /sources/:source_id/fetch` → `SourceFetchesController#create`
- `POST /sources/:source_id/retry` → `SourceRetriesController#create`
- `POST /sources/:source_id/bulk_scrape` → `SourceBulkScrapesController#create`

## Effort Analysis

### Required Changes

1. **New Controllers** (3 files):

   - `app/controllers/source_monitor/source_fetches_controller.rb`
   - `app/controllers/source_monitor/source_retries_controller.rb`
   - `app/controllers/source_monitor/source_bulk_scrapes_controller.rb`

2. **Controller Code Migration**:

   - Extract `SourcesController#fetch` → `SourceFetchesController#create`
   - Extract `SourcesController#retry` → `SourceRetriesController#create`
   - Extract `SourcesController#scrape_all` → `SourceBulkScrapesController#create`
   - Move before_action filters and helper methods

3. **Routes Update**:

   - Update `config/routes.rb`
   - Update all route helpers throughout the codebase

4. **View Updates** (estimated 10+ files):

   - Update all `link_to` and `button_to` calls
   - Update all Turbo Stream rendering
   - Update all redirect paths

5. **Test Updates** (estimated 15+ files):
   - Controller tests for 3 new controllers
   - Integration tests
   - System tests
   - Update all route helper references

### Estimated Effort

- **Controller extraction:** 2 hours
- **Route and helper updates:** 1 hour
- **View updates:** 2 hours
- **Test updates:** 2 hours
- **Testing and debugging:** 1 hour
- **Total: 8 hours**

## Benefit Analysis

### Pros of RESTful Refactor

1. **Strict REST Compliance**: Controllers would follow textbook RESTful patterns
2. **Separation of Concerns**: Each action type would have its own controller
3. **Easier Testing**: Controller tests would be more focused

### Cons of RESTful Refactor

1. **Increased Complexity**: 3 additional controller files to maintain
2. **More Indirection**: Developers need to know which controller handles which action
3. **No Functional Improvement**: Same behavior, just different file organization
4. **Cognitive Overhead**: Less intuitive than simple member actions
5. **Breaking Change**: Would require updating all existing code and tests

### Current Approach Benefits

1. **Simple and Clear**: All source-related actions in one controller
2. **Well-Named**: Actions like `fetch`, `retry`, `scrape_all` are self-documenting
3. **Rails-Conventional**: Member actions are an accepted Rails pattern
4. **Easy to Locate**: Developers know where to find source actions
5. **Working Well**: No performance or maintenance issues

## Decision

**REFACTOR TO PURE RESTFUL CONTROLLER CONVENTIONS** ✋
