# Phase 4 Context: Code Quality & Conventions Cleanup

## User Vision
Comprehensive final pass ensuring all code follows Rails best practices. Fix everything including public API changes if needed.

## Essential Features
- Model conventions audit (validations, scopes, associations, concerns)
- Controller patterns audit (CRUD-only actions, before_actions, response patterns)
- Dead code removal (unused methods, unreachable branches, commented-out code)
- Service objects and query objects follow conventions

## Technical Preferences
- Fix everything approach -- rename/restructure even if it changes method signatures or route patterns
- Update tests to match any API changes
- Comprehensive pass, not surface-level

## Boundaries
- Must maintain all existing test coverage (tests updated, not removed)
- RuboCop zero violations maintained
- CI pipeline stays green

## Acceptance Criteria
1. All models follow Rails conventions (validations, scopes, associations, concerns)
2. All controllers follow CRUD-only patterns with proper before_actions
3. No dead code (unused methods, commented-out code removed)
4. All service objects follow single-responsibility pattern
5. Coverage baseline at least 60% smaller than original (per ROADMAP success criteria)
6. Zero RuboCop violations
7. CI fully green

## Decisions Made
- Fix everything: public API changes are acceptable if they improve conventions
- Comprehensive scope: models, controllers, services, dead code -- all areas
