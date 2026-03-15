---
phase: 7
plan: 03
title: Job Shallowness & Pipeline Cleanup
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: [sm-job, sm-architecture, sm-engine-test, rails-architecture, tdd-cycle]
files_modified:
  - app/jobs/source_monitor/import_opml_job.rb
  - app/jobs/source_monitor/scrape_item_job.rb
  - app/jobs/source_monitor/download_content_images_job.rb
  - app/jobs/source_monitor/favicon_fetch_job.rb
  - app/jobs/source_monitor/source_health_check_job.rb
  - app/jobs/source_monitor/import_session_health_check_job.rb
  - lib/source_monitor/import_sessions/opml_importer.rb
  - lib/source_monitor/scraping/runner.rb
  - lib/source_monitor/images/processor.rb
  - lib/source_monitor/scraping/enqueuer.rb
  - lib/source_monitor/scraping/state.rb
  - lib/source_monitor.rb
  - test/jobs/source_monitor/import_opml_job_test.rb
  - test/jobs/source_monitor/scrape_item_job_test.rb
  - test/jobs/source_monitor/download_content_images_job_test.rb
  - test/jobs/source_monitor/favicon_fetch_job_test.rb
  - test/jobs/source_monitor/source_health_check_job_test.rb
  - test/lib/source_monitor/import_sessions/opml_importer_test.rb
  - test/lib/source_monitor/scraping/runner_test.rb
  - test/lib/source_monitor/images/processor_test.rb
forbidden_commands: []
must_haves:
  truths:
    - "ImportOpmlJob perform method is <= 10 lines, delegating to ImportSessions::OPMLImporter"
    - "ScrapeItemJob perform method is <= 10 lines, rate-limiting logic removed from job"
    - "DownloadContentImagesJob perform method is <= 10 lines, delegating to Images::Processor"
    - "Scrape rate-limiting exists only in Scraping::Enqueuer, not duplicated in ScrapeItemJob (H5)"
    - "Swallowed exceptions in scraping/state.rb have Rails.logger.warn (M17 partial)"
  artifacts:
    - {path: "lib/source_monitor/import_sessions/opml_importer.rb", provides: "Extracted OPML import service", contains: "class OPMLImporter"}
    - {path: "lib/source_monitor/scraping/runner.rb", provides: "Extracted scrape runner", contains: "class Runner"}
    - {path: "lib/source_monitor/images/processor.rb", provides: "Extracted image processing service", contains: "class Processor"}
  key_links:
    - {from: "app/jobs/source_monitor/import_opml_job.rb", to: "lib/source_monitor/import_sessions/opml_importer.rb", via: "OPMLImporter.new(...).call"}
    - {from: "app/jobs/source_monitor/scrape_item_job.rb", to: "lib/source_monitor/scraping/runner.rb", via: "Runner.new(item).call"}
    - {from: "app/jobs/source_monitor/download_content_images_job.rb", to: "lib/source_monitor/images/processor.rb", via: "Processor.new(item).call"}
---
<objective>
Extract business logic from fat jobs to achieve "shallow jobs" convention: ImportOpmlJob -> OPMLImporter (H2), ScrapeItemJob -> Scraping::Runner + remove duplicate rate-limiting (H3+H5), DownloadContentImagesJob -> Images::Processor (H4). Also clean up FaviconFetchJob (M12), ImportSessionHealthCheckJob (M13), SourceHealthCheckJob (M14), swallowed exceptions (M17), and StalledFetchReconciler fragility (M18).
</objective>
<context>
@.claude/skills/sm-job/SKILL.md -- shallow job convention, queue architecture, job patterns
@.claude/skills/sm-architecture/SKILL.md -- pipeline architecture, module tree, extraction patterns
@.claude/skills/sm-engine-test/SKILL.md -- job testing, WebMock, factory helpers
@.claude/skills/rails-architecture/SKILL.md -- service object patterns, when to extract
@.claude/skills/tdd-cycle/SKILL.md -- TDD workflow

Key context: ImportOpmlJob has 160 lines of business logic (entry selection, dedup, source creation, broadcasting). ScrapeItemJob has rate-limiting that duplicates Scraping::Enqueuer logic. DownloadContentImagesJob orchestrates Item, ItemContent, and ActiveStorage. All violate the "shallow jobs" convention: jobs should contain only deserialization + delegation.
</context>
<tasks>
<task type="auto">
  <name>Extract ImportOpmlJob to OPMLImporter service (H2)</name>
  <files>
    app/jobs/source_monitor/import_opml_job.rb
    lib/source_monitor/import_sessions/opml_importer.rb
    lib/source_monitor.rb
    test/jobs/source_monitor/import_opml_job_test.rb
    test/lib/source_monitor/import_sessions/opml_importer_test.rb
  </files>
  <action>
1. Create lib/source_monitor/import_sessions/opml_importer.rb containing the business logic from ImportOpmlJob#perform. The class should accept the same arguments the job receives and expose a #call method.
2. Move all entry selection, deduplication, source creation, attribute building, broadcast, and error aggregation logic into OPMLImporter.
3. Reduce ImportOpmlJob#perform to: find records, guard nil, call OPMLImporter.new(...).call.
4. Add autoload declaration in lib/source_monitor.rb for ImportSessions::OPMLImporter.
5. Create test for OPMLImporter that covers the main import path. Move relevant tests from job test file to service test file, keeping job test focused on delegation.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/import_opml_job_test.rb test/lib/source_monitor/import_sessions/opml_importer_test.rb
  </verify>
  <done>
ImportOpmlJob#perform is <= 10 lines. OPMLImporter contains all import business logic. Both test files pass.
  </done>
</task>
<task type="auto">
  <name>Extract ScrapeItemJob logic + remove duplicate rate-limiting (H3+H5)</name>
  <files>
    app/jobs/source_monitor/scrape_item_job.rb
    lib/source_monitor/scraping/runner.rb
    lib/source_monitor/scraping/enqueuer.rb
    lib/source_monitor.rb
    test/jobs/source_monitor/scrape_item_job_test.rb
    test/lib/source_monitor/scraping/runner_test.rb
  </files>
  <action>
1. Create lib/source_monitor/scraping/runner.rb that handles pre-flight checks (scraping enabled?), state management (mark_processing!, mark_failed!, clear_inflight!), and delegates to ItemScraper.
2. Remove rate-limiting logic (time_until_scrape_allowed) from ScrapeItemJob. The Enqueuer already handles deferral at enqueue time (H5). If the Runner needs a safety check, have it call Enqueuer's existing rate-limit method rather than duplicating the computation.
3. Reduce ScrapeItemJob#perform to: find item, guard nil, call Scraping::Runner.new(item).call.
4. Add autoload for Scraping::Runner in lib/source_monitor.rb.
5. Write Runner tests covering: successful scrape, scraping disabled skip, failed scrape state cleanup. Keep job test focused on delegation and queue assignment.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/scrape_item_job_test.rb test/lib/source_monitor/scraping/runner_test.rb
  </verify>
  <done>
ScrapeItemJob#perform is <= 10 lines. Rate-limiting exists only in Enqueuer. Runner handles all business logic. Tests pass.
  </done>
</task>
<task type="auto">
  <name>Extract DownloadContentImagesJob to Images::Processor (H4)</name>
  <files>
    app/jobs/source_monitor/download_content_images_job.rb
    lib/source_monitor/images/processor.rb
    lib/source_monitor.rb
    test/jobs/source_monitor/download_content_images_job_test.rb
    test/lib/source_monitor/images/processor_test.rb
  </files>
  <action>
1. Create lib/source_monitor/images/processor.rb that takes an Item and handles: building ItemContent, downloading images via Images::Downloader, creating ActiveStorage blobs, rewriting HTML, updating the item.
2. Reduce DownloadContentImagesJob#perform to: find item, guard nil, call Images::Processor.new(item).call.
3. Add autoload for Images::Processor in lib/source_monitor.rb.
4. Write Processor tests with WebMock stubs for image downloads. Keep job test focused on delegation.
  </action>
  <verify>
PARALLEL_WORKERS=1 bin/rails test test/jobs/source_monitor/download_content_images_job_test.rb test/lib/source_monitor/images/processor_test.rb
  </verify>
  <done>
DownloadContentImagesJob#perform is <= 10 lines. Images::Processor contains all image processing logic. Tests pass.
  </done>
</task>
<task type="auto">
  <name>Slim remaining fat jobs (M12, M13, M14)</name>
  <files>
    app/jobs/source_monitor/favicon_fetch_job.rb
    app/jobs/source_monitor/source_health_check_job.rb
    app/jobs/source_monitor/import_session_health_check_job.rb
    test/jobs/source_monitor/favicon_fetch_job_test.rb
    test/jobs/source_monitor/source_health_check_job_test.rb
  </files>
  <action>
1. M12: In FaviconFetchJob, move cooldown checking and attachment logic to a new private method in the existing Favicons module or into Source model. The job should delegate to a service call. If the logic is small enough (< 15 lines), moving it to Source#fetch_favicon! is acceptable per "models first" convention.
2. M13: In ImportSessionHealthCheckJob, extract lock acquisition, result merging, state updating, and broadcasting into ImportSessions::HealthCheckUpdater (can be a simple module method if the logic is < 30 lines, or a class if larger).
3. M14: In SourceHealthCheckJob, move toast_payload, broadcast_outcome, trigger_fetch_if_degraded into Health::SourceHealthCheckOrchestrator or extend the existing Health::SourceHealthCheck class.
4. Each job's perform method should become a short delegation.
  </action>
  <verify>
bin/rails test test/jobs/
  </verify>
  <done>
FaviconFetchJob, SourceHealthCheckJob, ImportSessionHealthCheckJob are all slim delegations. Business logic lives in service/model classes.
  </done>
</task>
<task type="auto">
  <name>Fix swallowed exceptions and fragile PG query (M17 partial, M18)</name>
  <files>
    lib/source_monitor/scraping/state.rb
    lib/source_monitor/fetching/stalled_fetch_reconciler.rb
  </files>
  <action>
1. M17 (partial -- scraping/state.rb only; feed_fetcher.rb handled by Plan 05): In scraping/state.rb, find `rescue StandardError => nil` or bare rescue blocks and add `Rails.logger.warn("[SourceMonitor] Swallowed exception in Scraping::State: #{e.class}: #{e.message}")`.
2. M18: In stalled_fetch_reconciler.rb, add a comment above the PG JSON operator query documenting: which SolidQueue version this was tested against, what the serialization format looks like, and that this should be re-verified on SolidQueue upgrades. Add a simple regression test if one doesn't exist.

Note: feed_fetcher.rb swallowed exceptions are handled by Plan 05 (which also modifies that file for L14+L15).
  </action>
  <verify>
grep -r "rescue.*nil" lib/source_monitor/scraping/ -- should return no silent rescues
  </verify>
  <done>
No silent exception swallowing in scraping/state.rb. StalledFetchReconciler PG query is documented with version info.
  </done>
</task>
</tasks>
<verification>
1. bin/rails test -- full suite passes
2. bin/rubocop app/jobs/ lib/source_monitor/import_sessions/ lib/source_monitor/scraping/ lib/source_monitor/images/ -- zero offenses
3. grep -c "def perform" app/jobs/source_monitor/import_opml_job.rb returns 1, and the method body is <= 10 lines
4. grep "time_until_scrape_allowed\|time_rate_limited" app/jobs/ returns no matches (rate-limiting only in lib/)
5. grep -r "rescue.*nil\|rescue StandardError$" lib/source_monitor/scraping/ returns no silent rescues
</verification>
<success_criteria>
- ImportOpmlJob, ScrapeItemJob, DownloadContentImagesJob business logic extracted to service classes (H2-H4)
- Duplicated scrape rate-limiting consolidated -- exists only in Scraping::Enqueuer (H5)
- FaviconFetchJob, SourceHealthCheckJob, ImportSessionHealthCheckJob slimmed (M12-M14)
- No silent exception swallowing in pipeline code (M17)
- StalledFetchReconciler PG query documented (M18)
- All job perform methods are <= 10 lines of delegation
- All tests pass with zero regressions
</success_criteria>
<output>
03-SUMMARY.md
</output>
