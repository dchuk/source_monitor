# Phase 1 Context: Install Generator Steps

## User Vision
Enhance the install generator to automatically handle the two most common Solid Queue setup failures in host apps: missing Procfile.dev jobs entry and missing recurring_schedule dispatcher wiring.

## Essential Features
- Generator creates Procfile.dev if missing (with web: and jobs: entries)
- Generator patches existing Procfile.dev to add jobs: entry (idempotent)
- Generator patches config/queue.yml dispatcher with recurring_schedule: config/recurring.yml
- Both steps integrated into the guided Setup::Workflow

## Technical Preferences
- **Procfile.dev:** Always create/patch -- maximum hand-holding. Create if missing, patch if exists.
- **Queue config:** Target `config/queue.yml` (Rails 8 default). Don't worry about legacy `solid_queue.yml` naming.
- Follow existing generator patterns (idempotent, skip-if-present, say_status output)

## Boundaries
- Don't modify any other config files (cable.yml, database.yml, etc.)
- Don't modify the initializer template
- Don't change existing generator steps (routes, initializer, recurring.yml)
- Don't add verification logic here (that's Phase 2)

## Acceptance Criteria
- `bin/rails generate source_monitor:install` creates Procfile.dev with web: + jobs: when none exists
- `bin/rails generate source_monitor:install` adds jobs: line to existing Procfile.dev without duplicating
- `bin/rails generate source_monitor:install` adds recurring_schedule to queue.yml dispatcher
- `bin/source_monitor install` (guided) runs both new steps
- All existing generator tests still pass
- New tests cover: fresh Procfile.dev, existing with entry, existing without entry, missing queue.yml

## Decisions Made
- Create Procfile.dev if missing (not just warn)
- Target config/queue.yml only (Rails 8 default), not solid_queue.yml
