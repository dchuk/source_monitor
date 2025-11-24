# Phase 17.03 Refactoring Execution Plan (2025-10-12)

## Workstreams & Owners (17.03.01)
- **Controllers & Views** — Owner: D. Demchuk — deliver sanitized search helper, shared pagination, and Turbo presenter layer.
- **Core Services** — Owner: J. Patel — modularize FetchRunner, ItemScraper, and RetentionPruner responsibilities.
- **Jobs & Scheduling** — Owner: L. Nguyen — standardize scraping job state transitions, cleanup job option parsing, and scheduler instrumentation/retry policies.
- **Front-End Pipeline** — Owner: M. Garcia — modernize Stimulus packaging, dropdown fallback, transition shim, and Tailwind rebuild automation.
- **Tooling & Metrics** — Owner: QA Guild — introduce Rubocop/Brakeman gating, SimpleCov baseline, and asset/test automation.

## Success Criteria & Coverage (17.03.02)
- **Controllers & Views**: Shared sanitization module reused by sources/items/log controllers; pagination helper with unit tests; Turbo presenter unit specs plus system regression for toast delivery.
- **Core Services**: FetchRunner split into lock manager + orchestration service with unit coverage and integration test updates; ItemScraper extraction with adapter contract tests; RetentionPruner strategies isolated with unit coverage for destroy/soft delete paths.
- **Jobs & Scheduling**: ScrapeItemJob leverages shared state helper with job tests; cleanup jobs share option parser module with unit tests; scheduler instrumentation emits event verified by integration test.
- **Front-End Pipeline**: Stimulus controllers load via import map/build pipeline with smoke test in system suite; dropdown fallback verified with JS integration; Tailwind rebuild command documented and executed in CI.
- **Tooling & Metrics**: Rubocop enforced in CI (passing run recorded); Brakeman baseline added; SimpleCov coverage target ≥90% for new code; asset lint/test tasks integrated.

## Sequencing & Dependencies (17.03.03)
1. **Tooling & Metrics** (enabling guardrails before refactors).
2. **Controllers & Views** (shared helpers reduce duplication ahead of service changes).
3. **Core Services** (builds on shared helpers for sanitization messaging).
4. **Jobs & Scheduling** (depends on service decomposition for scrape enqueue alignment).
5. **Front-End Pipeline** (requires controller presenter outputs stabilized).

## Monitoring & QA Checkpoints (17.03.04)
- Add instrumentation dashboards for scheduler events before deploying job changes.
- Run full system test suite after controller/view and front-end updates.
- Enable CI stages: `lint`, `security`, `test`, `assets` with gating.
- Schedule post-deploy log review for first run of refactored FetchRunner and ItemScraper.

## Follow-Up Tickets (17.03.05)
- Log backlog items for dashboard caching refinements and Mission Control integration once core refactors land.
- Document migration guidance for host apps adopting new helpers/presenters (README + upgrade notes).
- Track potential Pagy adoption experiment if manual pagination proves insufficient.

## Deliverables
- Execution plan stored here and referenced from roadmap tasks.
- Serves as baseline for future 17.x phases.
