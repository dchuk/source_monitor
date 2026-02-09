---
name: rails-lint
description: Runs RuboCop style fixes and Brakeman security scanning with auto-correction. Use when the user mentions linting, rubocop, brakeman, style fixes, code formatting, security scanning, or wants to clean up code quality issues.
tools: Read, Write, Edit, Bash, Glob, Grep
---

# RuboCop Style Fixes and Brakeman Security

## Project Conventions
- **Testing:** Minitest + fixtures (NEVER RSpec or FactoryBot)
- **Components:** ViewComponents for reusable UI (partials OK for simple one-offs)
- **Authorization:** Pundit policies (deny by default)
- **Jobs:** Solid Queue, shallow jobs, `_later`/`_now` naming
- **Frontend:** Hotwire (Turbo + Stimulus) + Tailwind CSS
- **State:** State-as-records for business state (booleans only for technical flags)
- **Architecture:** Rich models first, service objects for multi-model orchestration
- **Routing:** Everything-is-CRUD (new resource over new action)
- **Quality:** RuboCop (omakase) + Brakeman

## Lint Workflow

```
1. bin/rubocop -a     → Auto-fix safe style issues
2. bin/rubocop        → Review remaining issues
3. bin/brakeman -q    → Security vulnerability scan
4. Fix manually       → What auto-correct cannot handle
5. Re-run both        → Verify clean
```

## RuboCop Omakase Configuration

```ruby
# Gemfile
group :development do
  gem "rubocop-rails-omakase", require: false
end
```

```yaml
# .rubocop.yml
inherit_gem:
  rubocop-rails-omakase: rubocop.yml

AllCops:
  TargetRubyVersion: 3.3
  NewCops: enable
  Exclude:
    - "db/schema.rb"
    - "bin/**/*"
    - "vendor/**/*"
```

### Running RuboCop

```bash
bin/rubocop                    # Check all files
bin/rubocop app/models/        # Check directory
bin/rubocop -a                 # Auto-correct safe fixes
bin/rubocop -A                 # Auto-correct all (including unsafe)
bin/rubocop --display-cop-names # Show cop names
```

### Common Auto-Fixable Offenses

| Offense | Before | After |
|---------|--------|-------|
| Frozen string literal | (missing) | `# frozen_string_literal: true` |
| String quotes | `'single'` | `"double"` |
| Trailing whitespace | `code   ` | `code` |
| Hash syntax | `:key => value` | `key: value` |
| Redundant return | `return value` | `value` |
| Redundant self | `self.name` | `name` |

### Common Manual Fixes

#### Line Too Long

```ruby
# Before:
validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }

# After:
validates :email,
          presence: true,
          uniqueness: { case_sensitive: false },
          format: { with: URI::MailTo::EMAIL_REGEXP }
```

#### Method Too Long

```ruby
# Extract private methods to keep actions concise
def create
  authorize Event
  @event = build_event
  if @event.save
    redirect_to @event, notice: t(".success")
  else
    render :new, status: :unprocessable_entity
  end
end

private

def build_event
  current_account.events.new(event_params)
end
```

#### Class Too Long

Extract concerns when models exceed the line limit:

```ruby
class User < ApplicationRecord
  include Authenticatable
  include HasProfile
  include Notifiable
end
```

### Disabling Cops Inline

Use sparingly with justification:

```ruby
order(Arel.sql(sort_column)) # rubocop:disable Rails/ReflectionClassName
```

### Project-Specific Overrides

```yaml
# .rubocop.yml
Metrics/MethodLength:
  Max: 20
  Exclude: ["test/**/*", "db/migrate/*"]

Metrics/ClassLength:
  Max: 200
  Exclude: ["test/**/*"]

Metrics/BlockLength:
  Exclude: ["test/**/*", "config/routes.rb"]

Rails/HasManyOrHasOneDependent:
  Enabled: true
```

## Brakeman Security Scanning

```ruby
# Gemfile
group :development do
  gem "brakeman", require: false
end
```

### Running Brakeman

```bash
bin/brakeman              # Full scan
bin/brakeman -q           # Quiet (warnings only)
bin/brakeman -f json -o brakeman.json  # JSON for CI
bin/brakeman -I           # Generate ignore file interactively
```

### Common Warnings and Fixes

#### SQL Injection

```ruby
# DANGEROUS:
Event.where("name LIKE '%#{params[:q]}%'")
# FIX:
Event.where("name LIKE ?", "%#{params[:q]}%")
```

#### Cross-Site Scripting

```ruby
# DANGEROUS:
raw(@event.description)
# FIX:
sanitize(@event.description, tags: %w[p br strong em])
```

#### Mass Assignment

```ruby
# DANGEROUS:
Event.new(params[:event])
# FIX:
Event.new(event_params)  # Use strong parameters
```

#### Open Redirect

```ruby
# DANGEROUS:
redirect_to(params[:return_to])
# FIX:
redirect_to(params[:return_to] || root_path, allow_other_host: false)
```

#### File Access

```ruby
# DANGEROUS:
send_file(params[:path])
# FIX:
filename = File.basename(params[:filename])
path = Rails.root.join("storage", "reports", filename)
send_file(path) if File.exist?(path)
```

#### Dynamic Render

```ruby
# DANGEROUS:
render params[:template]
# FIX:
ALLOWED = %w[about contact faq].freeze
render template if ALLOWED.include?(template)
```

### Ignoring False Positives

```json
// config/brakeman.ignore
{
  "ignored_warnings": [
    {
      "warning_type": "SQL Injection",
      "fingerprint": "abc123...",
      "note": "Arel.sql used with constant string, not user input"
    }
  ]
}
```

## CI Configuration

```yaml
# .github/workflows/lint.yml
name: Lint & Security
on: [push, pull_request]
jobs:
  rubocop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/rubocop
  brakeman:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/brakeman -q --no-pager
```

## Test File Linting

Test files should follow Minitest conventions. Check for:

```ruby
# CORRECT:
require "test_helper"
class EventTest < ActiveSupport::TestCase
  test "requires name" do
    # ...
  end
end

# WRONG (RSpec patterns should never appear):
# describe Event do
#   it "requires name" do
#     expect(event).to be_invalid
#   end
# end
```

## Lint Checklist

- [ ] `bin/rubocop -a` to auto-fix safe issues
- [ ] `bin/rubocop` to check remaining issues
- [ ] Fix remaining issues manually
- [ ] `bin/brakeman -q` to scan for security issues
- [ ] Fix all CRITICAL and HIGH Brakeman warnings
- [ ] Document ignored warnings with justification
- [ ] Re-run both tools to verify clean
- [ ] Run tests to ensure fixes don't break anything: `bin/rails test`
