---
phase: 2
plan: 3
title: "Favicon Fetch Triggers: Source Creation and Feed Success"
wave: 2
depends_on: [1]
must_haves:
  - "FaviconFetchJob enqueued after source creation in SourcesController#create"
  - "FaviconFetchJob enqueued after successful feed fetch in SourceUpdater#update_source_for_success when favicon not attached"
  - "Favicon fetch only triggered when favicons enabled and ActiveStorage defined"
  - "Import OPML flow triggers favicon fetch for each created source"
  - "Cooldown respected: favicon not re-fetched within retry_cooldown_days of last failed attempt"
  - "Integration tests verify end-to-end favicon trigger flow"
  - "All existing tests pass, bin/rubocop zero offenses"
skills_used: []
---

# Plan 03: Favicon Fetch Triggers: Source Creation and Feed Success

## Objective

Wire FaviconFetchJob into the source lifecycle: trigger on source creation (controller + OPML import) and on successful feed fetches when favicon is missing. REQ-FAV-03.

## Context

- `@app/controllers/source_monitor/sources_controller.rb` -- create action (lines 54-62) for manual source creation trigger
- `@lib/source_monitor/fetching/feed_fetcher/source_updater.rb` -- update_source_for_success (lines 14-39) for feed success trigger
- `@app/jobs/source_monitor/import_opml_job.rb` -- OPML import creates sources in bulk
- `@app/jobs/source_monitor/favicon_fetch_job.rb` -- the job created in Plan 01 (must exist before this plan executes)

This plan depends on Plan 01 because it references FaviconFetchJob which is created there. No file overlap with Plan 02 (which modifies views/helpers only). This plan modifies: sources_controller.rb, source_updater.rb, import_opml_job.rb, and creates integration tests.

## Tasks

### Task 1: Trigger favicon fetch on manual source creation

**Files:** `app/controllers/source_monitor/sources_controller.rb`

In the `create` action (line 54-62), after `@source.save` succeeds but before the redirect, enqueue the favicon job:

Current:
```ruby
def create
  @source = Source.new(source_params)

  if @source.save
    redirect_to source_monitor.source_path(@source), notice: "Source created successfully"
  else
    render :new, status: :unprocessable_entity
  end
end
```

Replace with:
```ruby
def create
  @source = Source.new(source_params)

  if @source.save
    enqueue_favicon_fetch(@source)
    redirect_to source_monitor.source_path(@source), notice: "Source created successfully"
  else
    render :new, status: :unprocessable_entity
  end
end
```

Add a private method:
```ruby
def enqueue_favicon_fetch(source)
  return unless defined?(ActiveStorage)
  return unless SourceMonitor.config.favicons.enabled?
  return if source.website_url.blank?

  SourceMonitor::FaviconFetchJob.perform_later(source.id)
rescue StandardError => error
  Rails.logger.warn("[SourceMonitor] Failed to enqueue favicon fetch: #{error.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
end
```

**Tests:** `test/controllers/source_monitor/sources_controller_favicon_test.rb`

Create a separate controller test file to avoid merge conflicts:
- Test create with website_url enqueues FaviconFetchJob (use assert_enqueued_with)
- Test create without website_url does not enqueue FaviconFetchJob
- Test create with favicons disabled does not enqueue FaviconFetchJob
- Test create failure (invalid source) does not enqueue FaviconFetchJob

### Task 2: Trigger favicon fetch on successful feed fetch

**Files:** `lib/source_monitor/fetching/feed_fetcher/source_updater.rb`

In `update_source_for_success` (lines 14-39), after `source.update!(attributes)` on line 39, add favicon fetch enqueue:

Add after `source.update!(attributes)` (line 39):
```ruby
enqueue_favicon_fetch_if_needed
```

Add a private method to the class:
```ruby
def enqueue_favicon_fetch_if_needed
  return unless defined?(ActiveStorage)
  return unless SourceMonitor.config.favicons.enabled?
  return if source.website_url.blank?
  return if source.respond_to?(:favicon) && source.favicon.attached?

  # Check cooldown via metadata
  last_attempt = source.metadata&.dig("favicon_last_attempted_at")
  if last_attempt.present?
    cooldown_days = SourceMonitor.config.favicons.retry_cooldown_days
    return if Time.parse(last_attempt) > cooldown_days.days.ago
  end

  SourceMonitor::FaviconFetchJob.perform_later(source.id)
rescue StandardError => error
  Rails.logger.warn(
    "[SourceMonitor::SourceUpdater] Failed to enqueue favicon fetch for source #{source.id}: #{error.message}"
  ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
end
```

This duplicates some of the cooldown logic from the job itself (belt-and-suspenders). The reason is to avoid enqueuing unnecessary jobs when we can cheaply check in the updater. The job also checks on its own as a safety net.

**Tests:** `test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb`

Create a separate test file:
- Test update_source_for_success enqueues FaviconFetchJob when favicon not attached
- Test update_source_for_success does NOT enqueue when favicon already attached
- Test update_source_for_success does NOT enqueue when within cooldown period
- Test update_source_for_success does NOT enqueue when favicons disabled
- Test update_source_for_success does NOT enqueue when website_url blank
- Test update_source_for_success does NOT error when enqueue fails (rescued)
- Test update_source_for_not_modified does NOT enqueue favicon (we only trigger on success with content)

### Task 3: Trigger favicon fetch for OPML-imported sources

**Files:** `app/jobs/source_monitor/import_opml_job.rb`

Read the existing import_opml_job.rb to understand where sources are created. After each source is successfully created/saved in the import loop, enqueue a favicon fetch.

Find the source creation loop and add after each successful source.save! or source.create!:
```ruby
SourceMonitor::FaviconFetchJob.perform_later(source.id) if should_fetch_favicon?(source)
```

Add a private method:
```ruby
def should_fetch_favicon?(source)
  defined?(ActiveStorage) &&
    SourceMonitor.config.favicons.enabled? &&
    source.website_url.present?
rescue StandardError
  false
end
```

**Tests:** `test/jobs/source_monitor/import_opml_favicon_test.rb`

- Test that OPML import with sources having website_url enqueues FaviconFetchJob for each
- Test that OPML import with sources lacking website_url does not enqueue
- Test that OPML import with favicons disabled does not enqueue

### Task 4: Integration test for end-to-end favicon flow

**Files:** `test/integration/source_monitor/favicon_integration_test.rb`

Create an integration test that verifies the full flow:

1. Create a source via POST to sources_controller
2. Assert FaviconFetchJob was enqueued
3. Perform the job with WebMock stubs for favicon discovery
4. Assert favicon is attached to the source
5. Verify the source show page renders without error

Use `with_queue_adapter(:test)` and `assert_enqueued_with` for job assertions.

Also test the negative path:
- Create source without website_url, verify no job enqueued
- Create source with favicons disabled, verify no job enqueued

**Tests:** This task IS the test.

## Files

| Action | Path |
|--------|------|
| MODIFY | `app/controllers/source_monitor/sources_controller.rb` |
| MODIFY | `lib/source_monitor/fetching/feed_fetcher/source_updater.rb` |
| MODIFY | `app/jobs/source_monitor/import_opml_job.rb` |
| CREATE | `test/controllers/source_monitor/sources_controller_favicon_test.rb` |
| CREATE | `test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb` |
| CREATE | `test/jobs/source_monitor/import_opml_favicon_test.rb` |
| CREATE | `test/integration/source_monitor/favicon_integration_test.rb` |

## Verification

```bash
bin/rails test test/controllers/source_monitor/sources_controller_favicon_test.rb test/lib/source_monitor/fetching/feed_fetcher/source_updater_favicon_test.rb test/jobs/source_monitor/import_opml_favicon_test.rb test/integration/source_monitor/favicon_integration_test.rb
bin/rails test test/controllers/source_monitor/sources_controller_test.rb
bin/rubocop app/controllers/source_monitor/sources_controller.rb lib/source_monitor/fetching/feed_fetcher/source_updater.rb app/jobs/source_monitor/import_opml_job.rb
```

## Success Criteria

- Creating a source via UI enqueues FaviconFetchJob when website_url present
- Successful feed fetch enqueues FaviconFetchJob when favicon not attached and outside cooldown
- OPML import enqueues FaviconFetchJob for each imported source with website_url
- All triggers respect the enabled? guard and ActiveStorage check
- All triggers are wrapped in rescue to never break the main flow on failure
- Existing controller, job, and updater tests still pass
- Zero RuboCop offenses
