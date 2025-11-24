## Relevant Files

- `lib/source_monitor/setup` - Entry point for setup orchestration services/Thor commands.
- `lib/tasks/source_monitor.rake` - Rake interfaces for setup/verification tasks.
- `bin/source_monitor` - CLI wrapper for invoking setup workflow.
- `config/initializers/source_monitor.rb` - Installer-generated initializer that may need automated edits.
- `docs/setup.md` - Developer-facing setup checklist documentation.
- `test/lib/source_monitor/setup` - Unit tests for setup orchestration services.
- `test/tasks/source_monitor_setup_test.rb` - Tests covering rake task behavior.

### Notes

- Add/adjust unit tests alongside new services and rake tasks to keep coverage high.
- Prefer Thor/Rails generator patterns already used in the engine for consistent prompts.

## Instructions for Completing Tasks

IMPORTANT: As you complete each task, check it off by changing `- [ ]` to `- [x]`. Update after every sub-task once they are added.

## Tasks

- [x] 0.0 Create feature branch
  - [x] 0.1 Create and checkout `feature/setup-workflow-streamlining`
- [ ] 1.0 Build prerequisite detection and dependency helpers
  - [x] 1.1 Design dependency checker interface (Ruby/Rails/Postgres/Node/Solid Queue)
  - [x] 1.2 Implement version detection services with unit tests (TDD)
  - [x] 1.3 Add remediation guidance mapping (error messages) with tests
  - [x] 1.4 Wire helpers into CLI task to block/skip steps appropriately
- [x] 2.0 Implement guided setup command/workflow
  - [x] 2.1 Scaffold Thor/Rails task entry point with prompts, ensuring specs cover CLI flow
  - [x] 2.2 Automate Gemfile injection + `bundle install` and cover via integration-style tests/mocks
  - [x] 2.3 Automate `npm install` detection/execution with tests for both asset pipeline modes
  - [x] 2.4 Invoke install generator + mount path confirmation, validated by tests against dummy app
  - [x] 2.5 Copy migrations and deduplicate Solid Queue tables with regression tests
  - [x] 2.6 Automate initializer patching (Devise hooks optional) with unit tests covering idempotency
  - [x] 2.7 Provide guided prompts for Devise wiring and ensure tests cover conditional behavior
- [x] 3.0 Add verification and telemetry tooling
  - [x] 3.1 Implement Solid Queue worker verification service with tests simulating worker availability
  - [x] 3.2 Implement Action Cable adapter verification (Solid Cable default, Redis optional) with tests
  - [x] 3.3 Add reusable `source_monitor:setup:verify` task leveraging verification services with coverage
  - [x] 3.4 Emit structured JSON + human-readable summaries; test serialization and logging
  - [x] 3.5 Optional telemetry output (file/webhook) guarded by feature flag with tests
- [x] 4.0 Refresh documentation and onboarding assets
  - [x] 4.1 Update `docs/setup.md` to mirror automated workflow, referencing new commands
  - [x] 4.2 Document rollback steps and optional Devise system test template
  - [x] 4.3 Ensure `.ai/tasks.md` references this slice and link to PRD/tasks documents
- [x] 5.0 Validate workflow end-to-end and define rollout
  - [x] 5.1 Run setup workflow inside fresh Rails dummy app; record findings/logs
  - [x] 5.2 Run workflow inside existing host scenario (dummy app variations); capture diffs
  - [x] 5.3 Execute full test suite (`bin/rails test`, targeted setup tests, linters) and document results
  - [x] 5.4 Draft release notes + rollout checklist (include CI verification task adoption plan)
