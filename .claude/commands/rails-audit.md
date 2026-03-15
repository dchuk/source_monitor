# Rails Best Practices Audit

Perform a comprehensive Rails best practices audit of the entire codebase. Use the rails-specific skills and agents to identify opportunities to simplify, refactor, and align with Rails conventions ("the Rails Way").

## Usage

```
/rails-audit                    # Full audit of entire codebase
/rails-audit models only        # Scope to specific layer
/rails-audit --changed-only     # Only audit changed files (git diff)
```

## Instructions

Launch a team of agents in parallel to explore the codebase across multiple dimensions. Each agent should use the relevant rails skills (see CLAUDE.md Skill Catalog) and search the web for best practices when skills are insufficient.

### Agent 1: Models & Concerns (rails-review agent)
- Fat-model anti-patterns: models doing too much vs. missing scopes/validations
- Concern hygiene: single-purpose? overused? should any be model methods?
- Business logic placement: logic in controllers/services that belongs in models
- ActiveRecord anti-patterns: raw SQL where scopes suffice, missing `includes`/`preload`
- Missing validations, unnecessary callbacks, state management patterns
- Check for state-as-records pattern compliance (booleans vs. state records)

### Agent 2: Controllers & Routes (rails-review agent)
- Everything-is-CRUD compliance: custom actions that should be separate resources
- Business logic leaking into controllers
- Strong parameters, before_actions, proper response handling
- RESTful route compliance (no custom `member`/`collection` verbs)
- Controller concerns: well-focused or kitchen-sink?

### Agent 3: Services, Jobs & Pipeline (rails-review agent)
- Service objects: single-responsibility, Result pattern compliance
- Job shallowness: jobs should only deserialize + delegate, no business logic
- Service objects that should be model methods or concerns (< 3 models = model method)
- Pipeline stages: consolidation opportunities, error handling
- Query objects: are complex queries properly extracted?

### Agent 4: Views, Frontend & Hotwire (rails-review agent)
- Turbo Frame/Stream best practices
- Stimulus controllers: small, focused, one behavior each
- View logic that should be presenters (SimpleDelegator) or ViewComponents
- Tailwind CSS patterns: repeated utility groups that should be components
- Partial organization and reuse

### Agent 5: Testing & Quality (rails-review agent)
- Test DRYness: repeated setup that should be helpers
- Factory helper consistency (`create_source!`, etc.)
- Testing behavior vs. implementation
- Missing coverage patterns (validations, scopes, edge cases)
- Test isolation and parallel-safety

## Output

Produce a markdown file at `RAILS_AUDIT.md` in the project root with:

```markdown
# Rails Best Practices Audit — [date]

## Executive Summary
[High-level findings count by severity]

## Findings by Category

### Category Name
#### Finding Title
- **Severity:** high/medium/low
- **File(s):** `path/to/file.rb:line_number`
- **Current:** [what it does now]
- **Recommended:** [what it should do, with code example if helpful]
- **Rationale:** [why this is better, link to Rails convention]
- **Effort:** quick (< 30 min) / short (< 2 hrs) / medium (< 1 day) / large (> 1 day)
```

Sort findings within each category by severity (high first), then by effort (quick first).

$ARGUMENTS
