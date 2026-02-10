# Testing

## Framework & Tools

- **Test Framework**: Minitest (Rails default)
- **System Tests**: Capybara + Selenium WebDriver (Chrome)
- **HTTP Mocking**: WebMock (disables all external connections) + VCR (recorded cassettes)
- **Coverage**: SimpleCov with branch coverage enabled
- **Profiling**: test-prof (TagProf, EventProf) + StackProf
- **Parallelization**: Built-in Rails parallel testing (configurable workers via `SOURCE_MONITOR_TEST_WORKERS`)

## Test Infrastructure

### Test Helper (`test/test_helper.rb`)
- Loads SimpleCov in CI or when `COVERAGE` env is set
- Configures Rails test environment pointing to dummy app
- Sets migration paths to include both engine and dummy migrations
- Uses `:test` ActiveJob queue adapter by default
- Fixtures loaded from `test/fixtures/`
- VCR cassettes stored in `test/vcr_cassettes/`
- WebMock allows localhost only
- Random test ordering enabled
- Configuration reset in every test via `SourceMonitor.reset_configuration!`

### test-prof Integration (`test/test_prof.rb`)
- `TestProf::BeforeAll::Minitest` for `before_all` blocks (shared expensive setup)
- `SourceMonitor::TestProfSupport::SetupOnce` -- `setup_once` alias for `before_all`
- `SourceMonitor::TestProfSupport::InlineJobs` -- `with_inline_jobs` helper
- `TestProf::MinitestSample` -- SAMPLE/SAMPLE_GROUPS env var support for focused runs

### Shared Test Helpers
- `create_source!(attributes = {})` -- factory method for creating test sources
- `with_queue_adapter(adapter)` -- temporarily switch ActiveJob adapter

## Test Categories

| Category | File Count | Path | Purpose |
|----------|-----------|------|---------|
| Unit (lib) | ~75 | `test/lib/source_monitor/` | Lib module tests |
| Model | ~10 | `test/models/source_monitor/` | Model validation, scopes, behavior |
| System | 6 | `test/system/` | Browser-driven end-to-end tests |
| Integration | 4 | `test/integration/` | Engine mounting, navigation, packaging |
| Example | 4 | `test/examples/` | Template and adapter examples |
| Task | 2 | `test/tasks/` | Rake task tests |
| Mailer | 1 | `test/mailers/` | Application mailer test |
| Module | 1 | `test/source_monitor_test.rb` | Top-level module tests |

**Total: ~124 test files**

## Test Structure

Tests mirror the source directory structure:

```
test/lib/source_monitor/
  configuration_test.rb
  feedjira_configuration_test.rb
  instrumentation_test.rb
  health/
    health_module_test.rb
    source_health_check_test.rb
    source_health_monitor_test.rb
    source_health_reset_test.rb
  pagination/
    paginator_test.rb
  scraping/
    bulk_result_presenter_test.rb
    bulk_source_scraper_test.rb
    enqueuer_test.rb
    item_scraper_test.rb
    item_scraper/
      adapter_resolver_test.rb
      persistence_test.rb
    scheduler_test.rb
    state_test.rb
  setup/
    bundle_installer_test.rb
    cli_test.rb
    dependency_checker_test.rb
    detectors_test.rb
    gemfile_editor_test.rb
    initializer_patcher_test.rb
    install_generator_test.rb
    migration_installer_test.rb
    node_installer_test.rb
    prompter_test.rb
    requirements_test.rb
    workflow_test.rb
    verification/
      action_cable_verifier_test.rb
      printer_test.rb
      runner_test.rb
      solid_queue_verifier_test.rb
      telemetry_logger_test.rb
  turbo_streams/
    stream_responder_test.rb
  release/
    runner_test.rb
```

## Dummy Application (`test/dummy/`)

Full Rails application used as the host app for testing:
- PostgreSQL database (`config/database.yml`)
- Solid Queue configuration (`config/solid_queue.yml`, `config/queue.yml`)
- Solid Cable configuration (`config/cable.yml`)
- Mission Control integration
- Custom STI model: `SourceMonitor::SponsoredSource` (tests model extensions)
- Extension concern: `DummySourceMonitor::SourceExtensions`
- `User` model for testing authentication
- Source Monitor initializer exercising the full configuration API

## CI Pipeline

### Test Job
1. Sets up PostgreSQL 15 service container
2. Installs Ruby 3.4.4, Node 20
3. Builds frontend assets (`npm run build`)
4. Creates and migrates test database
5. Runs full test suite with coverage (`bin/test-coverage`)
6. Enforces diff coverage (`bin/check-diff-coverage`)
7. Uploads coverage artifact
8. Captures system test screenshots on failure

### Release Verification Job
- Depends on lint, security, test jobs
- Runs `test/integration/release_packaging_test.rb` specifically
- Enforces diff coverage again

### Profiling Job (Nightly)
- Runs on schedule (`cron: "30 6 * * *"`)
- TagProf by type
- EventProf on `sql.active_record`
- StackProf on integration tests
- Enforces profiling guardrails (`bin/check-test-prof-metrics`)
- Uploads profiling artifacts

## Coverage

- Branch coverage enabled
- `refuse_coverage_drop :line` prevents regressions
- Coverage baseline tracked in `config/coverage_baseline.json` (lists uncovered lines per file)
- Diff coverage enforcement ensures new code is tested
- `SOURCE_MONITOR_SKIP_COVERAGE` env var to disable coverage collection
- `# :nocov:` annotations used for defensive/fallback code paths

## Notable Testing Patterns

- **Configuration Reset**: Every test resets `SourceMonitor.reset_configuration!` in `setup`
- **WebMock**: All external HTTP disabled; tests use stubs or VCR cassettes
- **Job Testing**: Tests use `:test` adapter; `with_inline_jobs` for synchronous execution
- **Parallel Safety**: Tests designed for parallel execution; use `SecureRandom.hex` for unique fixtures
- **Factory Method**: `create_source!` with `save!(validate: false)` for flexible test data
- **Setup Verification Tests**: `bin/check-setup-tests` ensures all setup files have corresponding tests
