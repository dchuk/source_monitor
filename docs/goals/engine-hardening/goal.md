# Engine Hardening: auth defaults, notification scoping, gem packaging

## Objective

Implement the three specced engine-hardening issues end-to-end and verified:

- #129 — Fail-closed engine access when no auth handler is configured (+ explicit `open_access`/demo opt-in)
- #130 — Scope notification toasts to prevent cross-user leakage (request-flash path AND background-broadcast path)
- #131 — Exclude `.claude` internals from the packaged gem, keep `sm-*` skills

Each issue's acceptance-criteria checkboxes must be satisfied and the repo gates must be green.

## Original Request

"these 3 issues" — referring to #129, #130, #131, which were just broken out of umbrella #128 (PRD #127) and given codebase-validated Technical Specs via `issues-to-specs`.

## Intake Summary

- Input shape: `existing_plan` — each issue already has a `## Technical Spec` with behavior slices, tracer bullet, posture, and acceptance-criteria mapping.
- Audience: SourceMonitor engine maintainer (dchuk) + host apps consuming the `source_monitor` gem.
- Authority: `requested` — user wants the work implemented.
- Proof type: `test`
- Completion proof: every acceptance-criteria checkbox on #129/#130/#131 checked, and all four gates green.
- Goal oracle: the four repo gates plus the new behavior-slice tests added per issue, mapped back to each issue's acceptance criteria.
- Likely misfire: (1) declaring done after planning/discovery only; (2) shipping #129 fail-closed without the `open_access` opt-in + dummy-app update landing together, breaking the dummy app and existing controller tests; (3) entangling all three fixes in one commit instead of one coherent commit per issue; (4) "fixing" #130 by deleting toasts rather than scoping/decontextualizing them.
- Blind spots considered: #129 is an intentional breaking change needing a CHANGELOG/upgrade note; #130 has TWO global-stream leak paths (`ApplicationController#broadcast_flash_toasts` for request flashes AND `Broadcaster#broadcast_toast` for background events) — both must be addressed; the three issues are independent (no blocker ordering) but each is its own vertical slice + commit; CI diff-coverage gate requires tests for every new rescue/fallback branch.
- Existing plan facts: the three GitHub issues and their Technical Specs are the authoritative plan. Preserve them; validate against current HEAD before writing.

## Goal Oracle

The oracle for this goal is:

`rbenv exec bin/rails test` (incl. new per-issue behavior tests) + `rbenv exec bin/rubocop` + `rbenv exec bin/brakeman --no-pager` + `cd test/dummy && rbenv exec bundle exec rails zeitwerk:check`, ALL green, with each acceptance-criteria checkbox on #129/#130/#131 satisfied by a named test or evidence.

The PM must keep comparing task receipts to this oracle. A passing single issue is not full completion — all three issues must be implemented, verified, and their checkboxes mapped to evidence before `full_outcome_complete: true`.

## Goal Kind

`existing_plan`

## Current Tranche

Continuous execution. Validate the three specs against HEAD, then implement one coherent reversible Worker package per issue (suggested order: #131 packaging → #130 notifications → #129 auth, lowest-to-highest blast radius), verifying each package against the gates before advancing. Review only at the final completion boundary unless a package's verification is rejected or its behavior turns out ambiguous. Finish only when all three issues are implemented, verified, and audited complete.

## Non-Negotiable Constraints

- Follow project conventions in `CLAUDE.md`: Minitest (no RSpec/FactoryBot), `create_source!`/`with_inline_jobs` helpers, `SourceMonitor.reset_configuration!` per test, Tailwind/Hotwire, RuboCop omakase, Brakeman clean.
- One coherent commit per issue (auto_commit is on); do not entangle the three fixes.
- #129 fail-closed enforcement and its `open_access`/demo opt-in + dummy-app update + CHANGELOG note must land together in the same package.
- #130 must address BOTH leak paths; request flashes stay response-local, background operational toasts are scoped or stripped of per-user/request context. Do not delete the toast feature.
- #131 must only touch gemspec file-selection + one packaging test; do not change gem metadata or dependencies.
- No new runtime dependency. No schema changes. Preserve existing public config/handler API shape.
- Run the full local CI equivalent (all four gates) before considering any package done; write tests for every new rescue/fallback branch (CI diff-coverage gate).
- Never read/output protected files (`config/master.key`, `.env*`, credentials, `*.key`/`*.pem`).

## Stop Rule

Stop only when a final audit proves all three issues are implemented, verified, and their acceptance criteria are satisfied.

Do not stop after plan validation or after a single issue's package passes — advance to the next issue's package.

Mark a specific package blocked (with a receipt) only if it genuinely needs owner input (e.g. confirming the `open_access` opt-in name, or whether background toasts should exist at all); keep doing the other safe local packages meanwhile.

## Slice Sizing

One Worker package per issue is the natural vertical slice — each delivers a verified, independently-committable outcome mapped to a real issue. #131 is small but legitimately isolated (gemspec + one test); it is not a "tiny task" anti-pattern. Each Worker completes its whole issue (code + tests + docs/CHANGELOG where the spec requires) before handing back.

## Canonical Board

Machine truth lives at:

`docs/goals/engine-hardening/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins.

## Run Command

```text
/goal Follow docs/goals/engine-hardening/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Run the bundled GoalBuddy update checker when available; mention a newer version without blocking.
4. Re-check intake: original request, existing-plan facts, authority, proof, blind spots, likely misfire.
5. Work only on the active board task.
6. Assign Scout, Judge, Worker, or PM according to the task.
7. Write a compact task receipt.
8. Update the board.
9. If safe local work remains, activate the next Worker package and continue.
10. Record any operator-escalation issue/PR decision in a receipt; `state.yaml` stays authoritative.
11. Review only at final completion (or rejected verification / ambiguity), not after every Worker.
12. Finish only with a Judge/PM audit receipt that maps all three issues' criteria + the four gates back to the original outcome and records `full_outcome_complete: true`.
