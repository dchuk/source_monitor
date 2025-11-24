# Streamlined Setup Workflow for SourceMonitor Engine

## 1. Introduction / Overview
Teams currently follow a long, error-prone checklist to integrate the SourceMonitor engine into either brand-new or existing Rails 8 hosts. Manual gem edits, generator invocations, migration copying, authentication wiring, and Solid Queue/Solid Cable verification create setup drift and delayed feedback when something fails. This PRD defines a streamlined workflow that combines authoritative checklists with guided automation (scripts/generators) so users can reliably install, mount, and validate the engine with minimal switching between docs and terminals. The primary goal is to reduce manual tasks and error risk when onboarding SourceMonitor into any Rails app that meets the core prerequisites.

## 2. Goals
- Reduce time-to-first-successful SourceMonitor dashboard load (including background job + Action Cable verification) to under 15 minutes for both new and existing hosts.
- Provide a single guided setup command (or task) that performs/coordinates all feasible installation steps while surfacing next actions inline.
- Deliver updated documentation/checklists that stay in sync with the guided workflow and clearly call out remaining manual steps.
- Ensure Solid Queue/Solid Cable (with optional Redis Action Cable fallback) are validated automatically before marking setup complete.
- Instrument the workflow to capture pass/fail telemetry for each step (stored locally/logged) to aid support and future improvements.

## 3. User Stories
- **New Rails app maintainer:** “As a developer bootstrapping a fresh Rails 8.0.2.1+ app, I want a single command that adds SourceMonitor, runs the install generator, copies migrations, and verifies Solid Queue so I can start monitoring feeds without memorizing every prerequisite.”
- **Existing app maintainer:** “As a developer integrating SourceMonitor into an established Rails codebase, I want the installer to detect what’s already configured (Devise, Solid Queue migrations, Action Cable adapter) and only prompt me for missing pieces.”
- **Release engineer:** “As the person responsible for the release checklist, I want deterministic logs from the setup workflow so I can confirm every environment (staging, prod) passes the same validation steps.”

## 4. Functional Requirements
1. Provide a new CLI entry point (rails source_monitor:setup`) that orchestrates the onboarding steps end-to-end, supporting both fresh and existing hosts.
2. The setup command must:
   - Detect prerequisite versions (Ruby ≥ 3.4.4, Rails ≥ 8.0.2.1, PostgreSQL, Node ≥ 18) and halt with actionable remediation steps when mismatched.
   - Offer to append the `source_monitor` gem declaration if missing, then run `bundle install` (respecting rbenv) with progress output.
   - Run `npm install` only if the host manages node tooling and dependencies changed.
   - Invoke `source_monitor:install` with a user-confirmed mount path (default `/source_monitor`) and confirm the engine route is reachable.
   - Copy migrations via `railties:install:migrations FROM=source_monitor`, deduplicate Solid Queue tables if already present, and run `db:migrate`.
   - Create/patch `config/initializers/source_monitor.rb` with sensible defaults plus TODO comments for any unresolved configuration (Mission Control, custom queues, etc.).
   - Offer guided prompts (Y/N) for optional Devise wiring, with snippets inserted only when the host uses Devise (detected via Bundler).
   - Verify Solid Queue worker availability by optionally starting a transient worker or pinging existing processes, logging failures with remediation.
   - Verify Action Cable by ensuring either Solid Cable tables exist or Redis adapter credentials are configured; provide auto-detection and optional smoke ping.
3. Emit a structured summary (JSON + human-readable table) at the end of the setup run showing which steps succeeded, which need manual follow-up, and links to docs.
4. Create an updated checklist document (living under `docs/setup.md`) that mirrors the automated steps, clarifies manual-only tasks (e.g., navigation link updates, Mission Control wiring), and references the new command.
5. Expose a reusable verification task (e.g., `rails source_monitor:verify_install`) that can be run in CI to confirm migrations, queues, and Action Cable remain healthy after upgrades.
6. Ensure the workflow supports Solid Queue/Solid Cable by default and optionally configures Redis for Action Cable when the host opts in (prompt + adapter switch helper).
7. Add minimal telemetry hooks (log lines or optional webhook) so support teams can request the last setup report when debugging customer installs.
8. Provide sample scripts or templates for integrating a basic Devise-backed system test (sign-in + visit mount path) but mark it as optional to keep scope aligned with must-have validations (engine + background job success).
9. Document how to roll back the setup (e.g., remove gem, initializer, route) to encourage experimentation without risk.

## 5. Non-Goals (Out of Scope)
- Supporting non-PostgreSQL databases or Rails versions below 8.0.2.1.
- Full automation of Devise or other authentication stacks (provide guidance and optional snippets only).
- Provisioning or managing Redis/Solid Queue infrastructure beyond verifying connectivity and migrations.
- Replacing the existing CI pipeline; the focus is on installation workflow, not release automation.
- Creating GUI installers or web-based setup wizards—command-line + documentation only.

## 6. Design Considerations
- Provide dry-run and verbose flags so advanced users can inspect actions without modifying their apps.
- Structure setup steps as discrete service objects to enable reuse in future generators and tests.
- Store mount path and adapter decisions in `config/source_monitor.yml` to keep the initializer tidy.
- When Redis is selected for Action Cable, generate template credentials entries and highlight security requirements.

## 7. Technical Considerations
- Rails generators for CLI interactions to reuse existing generator patterns and support prompts.
- Respect rbenv by invoking Ruby/Bundler via `ENV["RBENV_ROOT"]` shims (mirroring existing binstubs).
- Ensure idempotency: rerunning the setup command should detect completed steps and skip or re-verify without breaking the app.
- For migration deduplication, compare checksum filenames before copying to avoid duplicates in existing hosts.
- Telemetry/logging should default to local file output (e.g., `log/source_monitor_setup.log`) with an opt-in environment variable for remote reporting.

## 8. Success Metrics
- ≥80% of beta users report completing setup in ≤15 minutes (collected via follow-up survey/logs).
- Support tickets related to initial installation drop by 50% quarter-over-quarter.
- Automated verification task adopted in CI for at least 3 internal environments within two weeks of release.
- Zero critical setup regressions reported within the first month after launch (monitored via issue tracker).

## 9. Open Questions
- Should the setup command automatically create a nav link in host layouts, or simply print instructions?
- How should we detect whether `npm install` is necessary in hosts that vend their own asset pipeline (e.g., Propshaft, esbuild)?
- Do we need to version-gate the workflow for future Rails releases (8.1, 8.2), and how will we communicate incompatibilities?
- Is telemetry opt-in per run (flag) or opt-out (environment variable)?
