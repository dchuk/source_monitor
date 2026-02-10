# Tech Stack

## Core Platform

| Layer | Technology | Version |
|-------|-----------|---------|
| Language | Ruby | >= 3.4.0 (CI uses 3.4.4) |
| Framework | Rails | >= 8.0.3, < 9.0 (locked at 8.1.1) |
| Database | PostgreSQL | 15 (CI service image) |
| Background Jobs | Solid Queue | >= 0.3, < 3.0 (locked at 1.2.4) |
| WebSocket/Realtime | Solid Cable | >= 3.0, < 4.0 (locked at 3.0.12) |
| Frontend Interactivity | Turbo Rails | ~> 2.0 (locked at 2.0.20) |
| JS Framework | Stimulus (Hotwired) | ^3.2.2 |
| CSS Framework | Tailwind CSS | ^3.4.10 |
| Web Server | Puma | 7.1.0 |
| Asset Pipeline | Propshaft | 1.3.1 |

## Project Type

Mountable Rails 8 Engine gem (`source_monitor.gemspec`), distributed as a RubyGem. The engine uses `isolate_namespace SourceMonitor` and provides its own models, controllers, views, jobs, and frontend assets.

- **Version**: 0.2.1
- **Required Ruby**: >= 3.4.0
- **License**: MIT

## Feed Parsing & HTTP

| Purpose | Gem | Version |
|---------|-----|---------|
| RSS/Atom/JSON feed parsing | Feedjira | >= 3.2, < 5.0 (locked 4.0.1) |
| HTTP client | Faraday | ~> 2.9 (locked 2.14.0) |
| HTTP retry middleware | faraday-retry | ~> 2.2 |
| HTTP redirect following | faraday-follow_redirects | ~> 0.4 |
| HTTP gzip compression | faraday-gzip | ~> 3.0 |

## Content Scraping & Parsing

| Purpose | Gem | Version |
|---------|-----|---------|
| HTML parsing (fast, C-based) | Nokolexbor | ~> 0.5 (locked 0.6.2) |
| HTML parsing (standard) | Nokogiri | 1.18.10 (transitive) |
| Article content extraction | ruby-readability | ~> 0.7 |

## Search & Querying

| Purpose | Gem | Version |
|---------|-----|---------|
| Search/filter forms | Ransack | ~> 4.2 (locked 4.4.1) |

## Frontend Build Pipeline

| Tool | Purpose | Version |
|------|---------|---------|
| esbuild | JS bundling | ^0.23.0 |
| Tailwind CSS | Utility-first CSS | ^3.4.10 |
| PostCSS | CSS processing | ^8.4.45 |
| Autoprefixer | CSS vendor prefixes | ^10.4.20 |
| ESLint | JS linting | ^9.11.0 |
| Stylelint | CSS linting | ^16.8.0 |

Build orchestration via `package.json` scripts:
- `npm run build` -- builds both CSS (tailwindcss) and JS (esbuild)
- `cssbundling-rails` (~> 1.4) and `jsbundling-rails` (~> 1.3) bridge npm builds into the Rails asset pipeline

## JS Dependencies (Runtime)

| Package | Purpose |
|---------|---------|
| `@hotwired/stimulus` ^3.2.2 | Stimulus controllers for UI interactions |
| `stimulus-use` ^0.52.0 | Stimulus composable behaviors library |

## Testing Stack

| Tool | Purpose |
|------|---------|
| Minitest | Test framework (Rails default) |
| Capybara | System/integration test driver |
| Selenium WebDriver | Browser automation for system tests |
| WebMock | HTTP request stubbing |
| VCR | HTTP interaction recording/playback |
| SimpleCov | Code coverage (branch coverage enabled) |
| test-prof | Test profiling (TagProf, EventProf) |
| StackProf | Sampling profiler for performance analysis |

## Code Quality & Security

| Tool | Purpose |
|------|---------|
| RuboCop (rails-omakase) | Ruby/Rails linting (omakase style) |
| Brakeman | Static security analysis |
| ESLint | JavaScript linting |
| Stylelint | CSS linting |

## CI/CD

- **GitHub Actions** with 5 jobs: `lint`, `security`, `test`, `release_verification`, `profiling` (scheduled nightly)
- Ruby 3.4.4, Node 20
- PostgreSQL 15 as service container
- Diff coverage enforcement via custom `bin/check-diff-coverage`
- Test profiling guardrails via `bin/check-test-prof-metrics`
- Parallel test execution (configurable via `SOURCE_MONITOR_TEST_WORKERS`)
