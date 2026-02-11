# Directory Structure

## Top-Level Layout

```
source_monitor/
  app/                    # Rails engine application code
  bin/                    # Scripts (rubocop, test runners, CI checks)
  config/                 # Engine configuration (routes, tailwind, feedjira initializer)
  db/migrate/             # Engine migrations (24 migration files)
  docs/                   # Documentation
  examples/               # Example configurations and adapters
  lib/                    # Engine library code and rake tasks
  test/                   # Test suite
  tasks/                  # Rake task definitions (aliases)
  coverage/               # SimpleCov output (gitignored content)
  node_modules/           # NPM packages
  pkg/                    # Gem build output
  tmp/                    # Temporary files
```

## App Directory (`app/`)

```
app/
  assets/
    builds/source_monitor/     # Pre-built CSS and JS (committed)
      application.css          # Built Tailwind CSS output
      application.js           # Built esbuild JS output
    config/
      source_monitor_manifest.js
    images/source_monitor/     # SVGs and icons
    javascripts/source_monitor/
      application.js           # Stimulus app entry point
      turbo_actions.js         # Custom Turbo Stream actions
      controllers/
        async_submit_controller.js
        confirm_navigation_controller.js
        dropdown_controller.js
        modal_controller.js
        notification_controller.js
        select_all_controller.js
    stylesheets/source_monitor/
      application.tailwind.css # Tailwind input file
    svgs/source_monitor/       # SVG assets
  controllers/source_monitor/
    application_controller.rb
    dashboard_controller.rb
    fetch_logs_controller.rb
    health_controller.rb
    import_sessions_controller.rb
    items_controller.rb
    logs_controller.rb
    scrape_logs_controller.rb
    source_bulk_scrapes_controller.rb
    source_fetches_controller.rb
    source_health_checks_controller.rb
    source_health_resets_controller.rb
    source_retries_controller.rb
    source_turbo_responses.rb
    sources_controller.rb
    concerns/
      sanitizes_search_params.rb
  jobs/source_monitor/
    application_job.rb
    fetch_feed_job.rb
    import_opml_job.rb
    import_session_health_check_job.rb
    item_cleanup_job.rb
    log_cleanup_job.rb
    schedule_fetches_job.rb
    scrape_item_job.rb
    source_health_check_job.rb
  mailers/source_monitor/
    application_mailer.rb
  models/source_monitor/
    application_record.rb
    fetch_log.rb
    health_check_log.rb
    import_history.rb
    import_session.rb
    item.rb
    item_content.rb
    log_entry.rb
    scrape_log.rb
    source.rb
    concerns/
      loggable.rb
  views/source_monitor/
    dashboard/
      index.html.erb
      _fetch_schedule.html.erb
      _job_metrics.html.erb
      _recent_activity.html.erb
      _stat_card.html.erb
      _stats.html.erb
    fetch_logs/
      show.html.erb
    import_sessions/
      show.html.erb
      show.turbo_stream.erb
      _header.html.erb
      _sidebar.html.erb
      health_check/
        _progress.html.erb
        _row.html.erb
      steps/
        _configure.html.erb
        _confirm.html.erb
        _health_check.html.erb
        _navigation.html.erb
        _preview.html.erb
        _upload.html.erb
    items/
      index.html.erb
      show.html.erb
      _details.html.erb
      _details_wrapper.html.erb
    logs/
      index.html.erb
    scrape_logs/
      show.html.erb
    shared/
      _toast.html.erb
    sources/
      index.html.erb
      show.html.erb
      new.html.erb
      edit.html.erb
      _bulk_scrape_form.html.erb
      _bulk_scrape_modal.html.erb
      _details.html.erb
      _details_wrapper.html.erb
      _empty_state_row.html.erb
      _fetch_interval_heatmap.html.erb
      _form.html.erb
      _form_fields.html.erb
      _health_status_badge.html.erb
      _import_history_panel.html.erb
      _row.html.erb
```

## Lib Directory (`lib/source_monitor/`)

```
lib/
  source_monitor.rb               # Main entry point, requires, module definition
  source_monitor/
    version.rb                    # VERSION constant (0.2.1)
    engine.rb                     # Rails::Engine with initializers
    configuration.rb              # Configuration DSL (655 lines)
    events.rb                     # Event system (dispatch, callbacks)
    instrumentation.rb            # ActiveSupport::Notifications wrapper
    metrics.rb                    # In-memory counters/gauges
    http.rb                       # Faraday client builder
    model_extensions.rb           # Dynamic model concern/validation injection
    scheduler.rb                  # Source fetch scheduling with SKIP LOCKED
    health.rb                     # Health module setup
    realtime.rb                   # Realtime broadcasting setup
    feedjira_extensions.rb        # Feedjira customizations
    assets.rb                     # Asset management utilities

    analytics/                    # Query objects for dashboard metrics
      source_activity_rates.rb
      source_fetch_interval_distribution.rb
      sources_index_metrics.rb
    assets/                       # Asset bundling helpers
    dashboard/                    # Dashboard presenters and queries
      queries.rb
      quick_action.rb
      quick_actions_presenter.rb
      recent_activity.rb
      recent_activity_presenter.rb
      turbo_broadcaster.rb
      upcoming_fetch_schedule.rb
    fetching/                     # Feed fetching pipeline
      feed_fetcher.rb             # Core fetcher (627 lines)
      fetch_error.rb
      fetch_runner.rb
      retry_policy.rb
      stalled_fetch_reconciler.rb
    health/                       # Health monitoring
      import_source_health_check.rb
      source_health_check.rb
      source_health_monitor.rb
      source_health_reset.rb
    import_sessions/              # OPML import support
      entry_normalizer.rb
    items/                        # Item management
      item_creator.rb
      retention_pruner.rb
    jobs/                         # Job support modules
      cleanup_options.rb
      fetch_failure_subscriber.rb
      solid_queue_metrics.rb
      visibility.rb
    logs/                         # Unified log system
      entry_sync.rb
      filter_set.rb
      query.rb
      table_presenter.rb
    models/                       # Shared model concerns
      sanitizable.rb
      url_normalizable.rb
    pagination/                   # Pagination support
      paginator.rb
    realtime/                     # Realtime broadcasting
      adapter.rb
      broadcaster.rb
    release/                      # Release management
      changelog.rb
      runner.rb
    scrapers/                     # Scraper adapters
      base.rb
      readability.rb
      fetchers/
        http_fetcher.rb
      parsers/
        readability_parser.rb
    scraping/                     # Scraping orchestration
      bulk_result_presenter.rb
      bulk_source_scraper.rb
      enqueuer.rb
      item_scraper.rb
      item_scraper/
        adapter_resolver.rb
        persistence.rb
      scheduler.rb
      state.rb
    security/                     # Security modules
      authentication.rb
      parameter_sanitizer.rb
    setup/                        # Installation workflow
      bundle_installer.rb
      cli.rb
      dependency_checker.rb
      detectors.rb
      gemfile_editor.rb
      initializer_patcher.rb
      install_generator.rb
      migration_installer.rb
      node_installer.rb
      prompter.rb
      requirements.rb
      shell_runner.rb
      workflow.rb
      verification/
        action_cable_verifier.rb
        printer.rb
        result.rb
        runner.rb
        solid_queue_verifier.rb
        telemetry_logger.rb
    sources/                      # Source-specific support
      params.rb
      turbo_stream_presenter.rb
    turbo_streams/                # Turbo Stream helpers
      stream_responder.rb
  tasks/                          # Rake tasks
    recover_stalled_fetches.rake
    source_monitor_assets.rake
    source_monitor_setup.rake
    source_monitor_tasks.rake
    test_smoke.rake
```

## Test Directory (`test/`)

```
test/
  test_helper.rb                  # Test configuration and shared helpers
  test_prof.rb                    # test-prof integration
  source_monitor_test.rb          # Module-level tests
  fixtures/                       # Test fixtures
    vcr_cassettes/                # VCR recorded HTTP interactions
  dummy/                          # Full Rails dummy app for testing
    app/
    bin/
    config/
    db/
  examples/                       # Example integration tests
    advanced_template_test.rb
    basic_template_test.rb
    custom_adapter_example_test.rb
    docker_config_test.rb
  integration/                    # Integration tests
    engine_mounting_test.rb
    host_install_flow_test.rb
    navigation_test.rb
    release_packaging_test.rb
  lib/source_monitor/             # Unit tests mirroring lib/ structure
    configuration_test.rb
    feedjira_configuration_test.rb
    instrumentation_test.rb
    health/
    pagination/
    release/
    scraping/
    security/  (implicitly tested)
    setup/
    turbo_streams/
  mailers/
  models/source_monitor/          # Model tests
  system/                         # System/browser tests
    dashboard_test.rb
    dropdown_fallback_test.rb
    items_test.rb
    logs_test.rb
    mission_control_test.rb
    sources_test.rb
  tasks/                          # Rake task tests
```

## Key File Counts

| Category | Count |
|----------|-------|
| Ruby files (.rb) | ~324 |
| ERB templates (.erb) | ~48 |
| JavaScript files (.js) | ~14 |
| YAML configs (.yml) | ~16 |
| Test files (*_test.rb) | ~124 |
| Migrations | 24 |
| Stimulus controllers | 6 |
