# Dependencies

## Runtime Dependencies (gemspec)

These are declared in `source_monitor.gemspec` and required by any host app using the engine.

| Gem | Constraint | Purpose | Risk |
|-----|-----------|---------|------|
| rails | >= 8.0.3, < 9.0 | Core framework | Major version lock |
| cssbundling-rails | ~> 1.4 | CSS asset bundling bridge | Low |
| jsbundling-rails | ~> 1.3 | JS asset bundling bridge | Low |
| turbo-rails | ~> 2.0 | Hotwire Turbo for real-time updates | Medium - optional but recommended |
| feedjira | >= 3.2, < 5.0 | Feed parsing (RSS/Atom) | Core functionality |
| faraday | ~> 2.9 | HTTP client | Core functionality |
| faraday-retry | ~> 2.2 | Retry middleware | Low |
| faraday-follow_redirects | ~> 0.4 | Redirect handling | Low |
| faraday-gzip | ~> 3.0 | Compression support | Low |
| nokolexbor | ~> 0.5 | Fast HTML parsing (lexbor engine) | Medium - native extension |
| ruby-readability | ~> 0.7 | Article content extraction | Medium - older gem |
| solid_queue | >= 0.3, < 3.0 | Background job processing | Core functionality |
| solid_cable | >= 3.0, < 4.0 | Action Cable adapter | Real-time features |
| ransack | ~> 4.2 | Search/filter form builder | Medium |

## Optional Runtime Dependencies

Loaded with rescue from LoadError in `lib/source_monitor.rb`:
- `solid_queue` -- optional if host uses different Active Job backend
- `solid_cable` -- optional if host uses Redis or another Action Cable adapter
- `turbo-rails` -- optional but recommended for real-time updates
- `ransack` -- powers search forms when available

## Development Dependencies (Gemfile)

| Gem | Purpose |
|-----|---------|
| puma | Development web server |
| pg | PostgreSQL adapter |
| propshaft | Asset pipeline |
| rubocop-rails-omakase | Linting (Rails omakase style) |
| brakeman | Security scanning |

## Test Dependencies (Gemfile)

| Gem | Purpose |
|-----|---------|
| simplecov | Code coverage reporting |
| test-prof | Test profiling toolkit |
| stackprof | Stack sampling profiler |
| capybara | System test framework |
| webmock | HTTP stubbing |
| vcr | HTTP recording/playback |
| selenium-webdriver | Browser driver for system tests |

## JavaScript Dependencies (package.json)

### Runtime

| Package | Version | Purpose |
|---------|---------|---------|
| @hotwired/stimulus | ^3.2.2 | Stimulus JS framework |
| stimulus-use | ^0.52.0 | Composable Stimulus behaviors |

### Development

| Package | Version | Purpose |
|---------|---------|---------|
| esbuild | ^0.23.0 | JS bundling |
| tailwindcss | ^3.4.10 | CSS framework |
| postcss | ^8.4.45 | CSS transformation |
| autoprefixer | ^10.4.20 | CSS vendor prefixes |
| eslint | ^9.11.0 | JS linting |
| @eslint/js | ^9.11.0 | ESLint core config |
| stylelint | ^16.8.0 | CSS linting |
| stylelint-config-standard | ^36.0.0 | Stylelint standard config |

## Dependency Coupling Analysis

### Tight Coupling (hard to replace)
- **Rails 8.x** -- entire engine is built on Rails conventions
- **Feedjira** -- core feed parsing logic, deeply integrated in `Fetching::FeedFetcher`
- **Faraday** -- HTTP client used throughout `SourceMonitor::HTTP`, configurable via middleware stack
- **Solid Queue** -- integrated in engine initializer, scheduler, and job visibility system
- **PostgreSQL** -- uses `FOR UPDATE SKIP LOCKED`, `NULLS FIRST/LAST` SQL syntax

### Moderate Coupling (replaceable with effort)
- **Nokolexbor/Nokogiri** -- HTML parsing in scrapers and OPML import
- **Ransack** -- used in model `ransackable_attributes` declarations and search forms
- **Tailwind CSS** -- all views use Tailwind utility classes scoped under `.fm-admin`

### Loose Coupling (easily replaceable)
- **Solid Cable** -- configurable via `config.realtime.adapter`, supports `:solid_cable`, `:redis`, `:async`
- **ruby-readability** -- wrapped in `Scrapers::Readability` adapter behind pluggable adapter interface
- **Turbo Rails** -- optional, loaded conditionally

## Version Constraints of Note

- Ruby >= 3.4.0 is a relatively aggressive minimum requirement
- Rails >= 8.0.3 pins to the latest major, narrowing host app compatibility
- Solid Queue has a wide range (0.3 to 3.0), suggesting early adoption with forward-looking flexibility
- PostgreSQL is the only supported database (uses PG-specific SQL features)
