# VBW Dev Agent Memory

## Project: source_monitor
- Rails engine gem for RSS/feed monitoring
- Ruby 3.4.4, Rails 8.x
- Test suite: 473 tests via `bin/rails test` (takes ~76 seconds)
- RuboCop uses `rubocop-rails-omakase` base config

## Key Learnings

### Shell/Bash in zsh
- `!` in zsh inline scripts causes `command not found` errors. Use `case` statements instead of `if ! ...` patterns.
- Use `IFS= read -r` when reading filenames from pipes to handle edge cases.

### RuboCop scope vs git scope
- RuboCop inspects ALL Ruby-like files (Gemfile, Rakefile, .gemspec, .rake, bin/*, config.ru), not just `.rb` files.
- `git ls-files -- '*.rb'` only matches `.rb` extensions. Plans scoped to `.rb` files may miss RuboCop violations in non-`.rb` Ruby files.
- `test/tmp/` contains untracked generated Rails app templates. These are NOT git-tracked but RuboCop scans them unless excluded.

### File structure
- `test/lib/tmp/install_generator/` contains test fixtures (1 tracked file: `config/initializers/source_monitor.rb`)
- `test/tmp/host_app_template_*` directories are generated test artifacts, not git-tracked
- `.rubocop.yml` is at project root, inherits from `rubocop-rails-omakase`

### Frozen string literal pragma
- Completed in commit `5f02db8` -- 113 files modified
- Added `test/tmp/**/*` to RuboCop exclude list

### RuboCop omakase ruleset details
- Only 45 cops enabled (out of 775 available)
- ALL Metrics cops disabled (ClassLength, MethodLength, BlockLength, etc.)
- After frozen_string_literal fix, codebase had zero remaining violations
- No `.rubocop.yml` exclusions needed for large files since Metrics cops are off
- Plan 02 completed with no code changes required
