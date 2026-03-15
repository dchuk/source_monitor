---
phase: 7
plan: 01
title: Model Correctness & Data Integrity
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-domain-model, sm-engine-test, tdd-cycle]
files_modified:
  - app/jobs/source_monitor/log_cleanup_job.rb
  - app/models/source_monitor/source.rb
  - app/models/source_monitor/item.rb
  - app/models/source_monitor/item_content.rb
  - app/models/source_monitor/import_history.rb
  - app/models/concerns/source_monitor/loggable.rb
  - app/models/source_monitor/fetch_log.rb
  - app/models/source_monitor/scrape_log.rb
  - app/models/source_monitor/health_check_log.rb
  - db/migrate/TIMESTAMP_align_health_status_default.rb
  - test/jobs/source_monitor/log_cleanup_job_test.rb
  - test/models/source_monitor/source_test.rb
  - test/models/source_monitor/item_test.rb
  - test/models/source_monitor/item_content_test.rb
  - test/models/source_monitor/import_history_test.rb
  - test/models/source_monitor/fetch_log_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "LogCleanupJob deletes LogEntry records before deleting FetchLog/ScrapeLog/HealthCheckLog records"
    - "Source health_status has inclusion validation matching HEALTH_STATUS_VALUES constant"
    - "DB default for health_status matches model default (migration changes DB to 'working')"
    - "sync_log_entry callback is defined in Loggable concern, not in individual log models"
    - "Item#restore! method exists and increments counter cache"
  artifacts:
    - {path: "app/models/concerns/source_monitor/loggable.rb", provides: "Consolidated sync_log_entry callback", contains: "sync_log_entry"}
    - {path: "app/models/source_monitor/source.rb", provides: "health_status validation + scraping scopes", contains: "HEALTH_STATUS_VALUES"}
    - {path: "app/models/source_monitor/item.rb", provides: "restore! method", contains: "def restore!"}
  key_links:
    - {from: "app/jobs/source_monitor/log_cleanup_job.rb", to: "app/models/source_monitor/log_entry.rb", via: "LogEntry.where(loggable_type:).delete_all before log deletion"}
---
<objective>
Fix model-layer correctness issues: LogCleanupJob orphaned records (H1), health_status default/validation mismatch (M1+M2), Item soft_delete restore symmetry (M3), duplicated sync_log_entry callback (M4), missing scraping scopes (L10), ItemContent Demeter violation (L11), ImportHistory validation gaps (L12).
</objective>
<context>
@.claude/skills/sm-domain-model/SKILL.md -- model relationships, Source state values, Loggable concern
@.claude/skills/sm-engine-test/SKILL.md -- test helpers, create_source! factory, parallel safety
@.claude/skills/tdd-cycle/SKILL.md -- TDD red-green-refactor workflow

Key context: LogCleanupJob uses batch.delete_all on FetchLog/ScrapeLog which skips dependent: :destroy callbacks, orphaning LogEntry records. Source has health_status default "working" in model but "healthy" in DB schema. Three log models duplicate identical sync_log_entry callbacks that belong in their shared Loggable concern. Item#soft_delete! decrements counter cache but has no restore! to re-increment.
</context>
<tasks>
<task type="auto">
  <name>Fix LogCleanupJob orphaned LogEntry records (H1)</name>
  <files>
    app/jobs/source_monitor/log_cleanup_job.rb
    test/jobs/source_monitor/log_cleanup_job_test.rb
  </files>
  <action>
In LogCleanupJob, before each batch.delete_all call on FetchLog/ScrapeLog/HealthCheckLog, first delete the corresponding LogEntry records:

```ruby
# Before deleting FetchLog batch:
SourceMonitor::LogEntry.where(loggable_type: "SourceMonitor::FetchLog", loggable_id: batch.select(:id)).delete_all
batch.delete_all
```

Apply this pattern to all three log type cleanup sections. Add tests that:
1. Create a FetchLog + its LogEntry
2. Run LogCleanupJob
3. Assert both FetchLog AND LogEntry are deleted (no orphans remain)
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/log_cleanup_job_test.rb
  </verify>
  <done>
LogCleanupJob deletes LogEntry records before corresponding log records. Test proves no orphaned LogEntry records remain after cleanup.
  </done>
</task>
<task type="auto">
  <name>Align health_status default and add validation (M1+M2)</name>
  <files>
    app/models/source_monitor/source.rb
    db/migrate/TIMESTAMP_align_health_status_default.rb
    test/models/source_monitor/source_test.rb
  </files>
  <action>
1. In source.rb, add HEALTH_STATUS_VALUES constant (use existing values from health module: %w[healthy working declining improving failing].freeze) and validates :health_status, inclusion: { in: HEALTH_STATUS_VALUES }.
2. Add scraping scopes (L10): `scope :scraping_enabled, -> { where(scraping_enabled: true) }` and `scope :scraping_disabled, -> { where(scraping_enabled: false) }`.
3. Create a migration to change the DB default from "healthy" to "working" (matching the model attribute declaration).
4. Write tests: invalid health_status rejected, valid values accepted, new Source gets "working" default, scraping scopes return correct records.

Note: Check what values the health module actually uses. The model says default "working", health module may use "healthy", "declining", "improving", "failing". Include all values that appear in the codebase.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/source_test.rb
  </verify>
  <done>
Source has HEALTH_STATUS_VALUES constant, inclusion validation on health_status, migration aligns DB default to "working", scraping_enabled/scraping_disabled scopes added.
  </done>
</task>
<task type="auto">
  <name>Add Item#restore! and fix counter cache symmetry (M3)</name>
  <files>
    app/models/source_monitor/item.rb
    test/models/source_monitor/item_test.rb
  </files>
  <action>
1. Add `restore!` method to Item that sets deleted_at to nil via update_columns and calls Source.increment_counter(:items_count, source_id). This is the symmetric counterpart to soft_delete!.
2. Write tests: restore! clears deleted_at, increments counter cache, raises on non-deleted item (or is idempotent -- follow the pattern soft_delete! uses).
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/item_test.rb
  </verify>
  <done>
Item has restore! method that clears deleted_at and increments source items_count. Tests verify counter cache symmetry with soft_delete!.
  </done>
</task>
<task type="auto">
  <name>Consolidate sync_log_entry into Loggable concern (M4)</name>
  <files>
    app/models/concerns/source_monitor/loggable.rb
    app/models/source_monitor/fetch_log.rb
    app/models/source_monitor/scrape_log.rb
    app/models/source_monitor/health_check_log.rb
    test/models/source_monitor/fetch_log_test.rb
  </files>
  <action>
1. Move the `after_save :sync_log_entry` callback and `sync_log_entry` private method into the Loggable concern's `included` block.
2. Remove the duplicate callback + method from FetchLog, ScrapeLog, and HealthCheckLog.
3. Verify the sync_log_entry method body is identical across all 3 models before consolidating. If there are differences, use the most complete version.
4. Add a test in fetch_log_test.rb (or existing Loggable test) that proves saving a FetchLog creates/syncs the corresponding LogEntry.
  </action>
  <verify>
bin/rails test test/models/
  </verify>
  <done>
sync_log_entry callback defined once in Loggable concern. FetchLog, ScrapeLog, HealthCheckLog no longer define it individually. grep -r "sync_log_entry" app/models/ returns only loggable.rb.
  </done>
</task>
<task type="auto">
  <name>Minor model improvements (L11, L12)</name>
  <files>
    app/models/source_monitor/item_content.rb
    app/models/source_monitor/import_history.rb
    test/models/source_monitor/item_content_test.rb
    test/models/source_monitor/import_history_test.rb
  </files>
  <action>
1. L11: In ItemContent#compute_feed_word_count, if the method reaches through the item association to get data, refactor to accept the needed value as a parameter or use a delegation. Review the actual code and apply the minimal fix.
2. L12: In ImportHistory, add JSONB attribute declarations for any JSONB columns that lack them (attribute :column_name, :json, default: -> { {} }). Add validates :imported_at, presence: true or similar chronological validation if appropriate.
3. Write/update tests for both changes.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/models/source_monitor/item_content_test.rb test/models/source_monitor/import_history_test.rb
  </verify>
  <done>
ItemContent compute method no longer violates Demeter. ImportHistory has proper JSONB declarations and validation. Tests pass.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes with zero failures
2. bin/rubocop app/models/ app/jobs/source_monitor/log_cleanup_job.rb -- zero offenses
3. grep -r "sync_log_entry" app/models/ returns only loggable.rb
4. grep "HEALTH_STATUS_VALUES" app/models/source_monitor/source.rb returns the constant
5. grep "def restore!" app/models/source_monitor/item.rb returns the method
</verification>
<success_criteria>
- LogCleanupJob cascades deletes to LogEntry records before deleting log records (H1)
- Source health_status has HEALTH_STATUS_VALUES constant and inclusion validation (M1+M2)
- DB migration aligns health_status default to "working" (M1)
- Item has restore! method with counter cache increment (M3)
- sync_log_entry callback lives only in Loggable concern (M4)
- Source has scraping_enabled/scraping_disabled scopes (L10)
- All tests pass with zero regressions
</success_criteria>
<output>
01-SUMMARY.md
</output>
