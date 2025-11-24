# SourceMonitor Rename Master Checklist

Use this to convert the engine, gem, and docs from **source_monitor / SourceMonitor** to **source_monitor / SourceMonitor** (gem to be published as `source_monitor`, module namespace `SourceMonitor`, tables prefixed `sourcemon_`). Update this file as you discover additional touch points.

## Repository & Packaging
- Rename `source_monitor.gemspec` ➜ `source_monitor.gemspec`; update `spec.name`, version require, metadata URLs (new GitHub slug `dchuk/source_monitor`, docs, changelog), summary/description, and release comments.
- Update `Gemfile`, `Gemfile.lock`, `test/dummy/Gemfile.lock`, and any `gem "source_monitor"` references (examples) to use `source_monitor`; regenerate locks.
- Move `lib/source_monitor/version.rb` ➜ `lib/source_monitor/version.rb` and change the module namespace to `SourceMonitor`.
- Ensure release scripts and packaging (`pkg/source_monitor-*.gem`, `bin/release`, `lib/source_monitor/release/*`) reflect the new gem/repo name.
- Update docs/AGENTS and `docs/gh-cli-workflow.md` to reference `github.com/dchuk/source_monitor`.

## Ruby Namespace & Entry Points
- Replace every `SourceMonitor` constant with `SourceMonitor` across `lib/`, `app/`, `test/`, `examples/`, and `test/dummy/`.
- Update `lib/source_monitor.rb` ➜ `lib/source_monitor.rb`, requiring the new version file and adjusting singleton helpers.
- Adjust `bin/rails`, `bin/*`, and any scripts referencing `lib/source_monitor/engine` to the new path.
- Confirm `SourceMonitor::Engine.table_name_prefix` supplies the new `sourcemon_` prefix.

## Directory & File Renames
- Rename every directory/file containing `source_monitor` to `source_monitor` (controllers, models, jobs, helpers, views, assets, lib modules, tests, generators, examples, dummy app, VCR cassettes).
- Update asset paths: `app/assets/config/source_monitor_manifest.js`, stylesheets, javascripts, images, svgs, builds, etc., to `source_monitor`.
- Generator templates: `lib/generators/source_monitor/**` ➜ `source_monitor/**`, template names (`source_monitor.rb.tt`) and targets (`config/initializers/source_monitor.rb`).

## Database Schema & Migrations
- Rename migration classes/files from `SourceMonitor` to `SourceMonitor`; update table names (`source_monitor_sources` ➜ `sourcemon_sources`, etc.) throughout migrations.
- Add safe migrations that rename existing tables/indexes (`rename_table :source_monitor_sources, :sourcemon_sources`) so live installs migrate cleanly.
- Update models’ `self.table_name`, schema dumps (`test/dummy/db/schema.rb`), SQL snippets, and seeds to `sourcemon_*`.
- Adjust recurring schedule keys (`test/dummy/config/recurring.yml`) and Solid Queue references to the new prefix.

## Jobs, Queues, Instrumentation
- Change default queue names/helpers from `source_monitor_fetch` / `source_monitor_scrape` to `source_monitor_fetch` / `source_monitor_scrape` (README, AGENTS, docs, configuration code, tests).
- Update Solid Queue configs (`examples/advanced_host/files/config/solid_queue.yml`) and worker docs.
- Rename ActiveSupport notification namespaces (`source_monitor.fetch.*`, `source_monitor.scheduler.run`, etc.) plus any subscribers/docs referencing them.
- Update recurring job identifiers, `SIMPLECOV_COMMAND_NAME`, and instrumentation strings using the old name.

## Assets & Front-End
- Adjust Tailwind/ESBuild scripts (package.json, package-lock, config/tailwind.config.js) to point at `source_monitor` asset directories.
- Rename helper methods (`source_monitor_stylesheet_bundle_tag`, etc.) and their tests to `source_monitor_*`.
- Ensure DOM IDs/data attributes and Stimulus controllers referencing the old name are updated.

## Configuration, Generators & Initializers
- Update installer commands (`rails source_monitor:install`, `SourceMonitor.configure`) in README, docs, `.ai` references, and generator templates.
- Change initializer filenames (`config/initializers/source_monitor.rb`) in code samples, docs, and tests.
- Adjust mount paths and route helpers (`source_monitor.sources_path`, `mount SourceMonitor::Engine => "/source_monitor"`) across controllers, views, and system tests.

## Scripts, Env Vars & Tooling
- Rename Rake namespaces/tasks (`namespace :source_monitor`) to `source_monitor`.
- Update scripts (`bin/test-coverage`, `bin/release`, `test/support/host_app_harness.rb`, `test/integration/release_packaging_test.rb`) plus env vars (`SOURCE_MONITOR_TEST_WORKERS`, `SOURCE_MONITOR_GEM_PATH`, etc.) to `SOURCE_MONITOR_*`.
- Modify CI workflow env names and DB names (`source_monitor_test` ➜ `sourcemon_test`) in `.github/workflows/ci.yml` and docker/example configs.
- Refresh `.env` samples, `config/application.yml.sample`, and docs referencing `config/source_monitor.yml`.

## Tests & Fixtures
- Rename test modules/directories under `test/**/source_monitor` to `source_monitor`; update assertions referencing route helpers, queue names, metric names, etc.
- Move VCR cassette folders (`test/vcr_cassettes/source_monitor/**`) and update references in tests.
- Update dummy host files (`test/dummy/app/**`, initializers, routes, bin/dev/jobs) to the new name.

## Documentation & Guides
- Rebrand all markdown/docs (`README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/*.md`, `AGENTS.md`, `.ai/*.md`) to SourceMonitor, including command snippets, route paths, queue names, notification namespaces, and environment variable names.
- Update GitHub badges/links to the new repo (`dchuk/source_monitor`).

## Example Apps & Templates
- Rename example template outputs (`source_monitor_basic` ➜ `source_monitor_basic`, etc.) and update template commands/mount paths/instrumentation docs.
- Update docker example env vars, compose files, and docs to the new naming.

## External References & Release Process
- Change gemspec metadata URIs to the new GitHub repo once renamed.
- Update release checklist in `CHANGELOG.md` (commands, gem names, push targets) and any automation referencing the old name.
- Plan the RubyGems release under `source_monitor` and remove references to the old gem in docs once the rename is complete.
- After all renames, rebuild assets, regenerate lockfiles, rerun coverage baselines, and create follow-up migrations/tags before publishing `source_monitor` 0.1.0.

Keep this checklist as the single source of truth while executing the SourceMonitor rebrand.
