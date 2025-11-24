# SourceMonitor Engine - Project Overview & Capabilities

## Project Overview

SourceMonitor Engine is a production-ready Rails 8 mountable engine for aggregating, monitoring, and managing RSS/Atom/JSON feeds at scale. Built with Rails 8 defaults and minimal dependencies, it provides a complete solution for feed ingestion, content scraping, and real-time monitoring.

### Core Philosophy

- **Rails 8 Native**: Leverages Solid Queue, Solid Cache, and Turbo
- **Minimal Dependencies**: Rails + Tailwind + essential feed/HTTP gems only
- **Testable Vertical Slices**: Every phase delivers working, testable functionality
- **Host App Extensibility**: Hooks and callbacks for custom behavior
- **Production Ready**: Built-in observability, error recovery, and performance optimization
- **TDD & Full Test Coverage**: Uses minitest and rails testing best practices to maximize reliability

### Technology Stack

- **Framework**: Rails 8
- **Background Jobs**: Solid Queue (Rails 8 default)
- **Caching**: Solid Cache (Rails 8 default)
- **Real-time Updates**: Turbo (Rails 8 default)
- **Styling**: Tailwind CSS
- **HTTP Client**: Faraday with retry middleware
- **Feed Parsing**: Feedjira
- **Content Extraction**: Ruby Readability
- **Testing**: MiniTest with VCR/WebMock

---

## Core Capabilities

### 1. Feed Source Management

**Add and Configure Multiple Sources**

- Create unlimited feed sources with custom settings
- Configure per-source fetch intervals (hourly to weekly)
- Set custom headers for authentication/API keys
- Store source metadata in flexible JSONB fields
- Validate and normalize feed URLs automatically

**Source Health Monitoring**

- Track success/failure rates over time
- Automatic backoff for failing sources
- Auto-pause sources after repeated failures
- Auto-recovery detection and resume
- Visual health status indicators in UI

**Source Status Control**

- Manually pause/resume individual sources
- Bulk enable/disable operations
- Schedule future activation times
- Track last fetch timestamp and duration
- Monitor HTTP status codes and errors

---

### 2. Feed Fetching & Processing

**Intelligent HTTP Fetching**

- Automatic feed format detection (RSS 0.9-2.0, Atom, JSON Feed)
- Conditional GET with ETag and Last-Modified support
- 304 Not Modified handling to reduce bandwidth
- Configurable timeouts and retry strategies
- Per-host rate limiting to respect server limits
- Automatic redirect following with limits
- Gzip compression support

**Scheduled Fetching**

- Fixed interval scheduling (every N hours)
- Adaptive scheduling based on posting frequency
- Exponential backoff for failing sources
- Jitter to prevent thundering herd
- SELECT FOR UPDATE SKIP LOCKED for concurrency
- Manual fetch triggering from UI or API

**Item Creation & Deduplication**

- GUID-based duplicate prevention
- Content fingerprint fallback for feeds without GUIDs
- Idempotent upsert operations
- Duplicate detection across refetches
- Counter cache updates for performance
- Comprehensive metadata extraction

---

### 3. Content Metadata Extraction

**Standard Feed Fields**

- Title, URL, GUID, canonical URL
- Author name and authors array
- Publication and update timestamps
- Summary and full content (HTML/text)
- Language and copyright information

**Extended Metadata**

- Categories, tags, and keywords
- Media enclosures (podcasts, videos, images)
- Media thumbnails and content objects
- Comments URL and count
- Custom metadata in JSONB storage
- Multiple namespace support (DC, Media RSS, etc.)

**Feed-Level Metadata**

- Feed format and version detection
- Feed-level metadata storage
- HTTP response headers capture
- Feed size tracking
- Item counts per fetch

---

### 4. Content Scraping

**Full Article Extraction**

- Toggle content scraping per source
- Automatic or manual scraping triggers
- Multiple storage layers (raw HTML + extracted content)
- Readability-based content extraction
- Custom CSS selector support
- JavaScript rendering support configuration

**Scraper Adapters**

- Extensible adapter interface
- Built-in Readability adapter
- Custom adapter support via configuration
- Adapter-specific settings per source
- Fallback strategies for extraction failures

**Scraping Control**

- Auto-scrape new items on fetch
- Manual scrape individual items from UI
- Bulk scraping operations
- Scrape retry logic with backoff
- Per-source scraping configuration
- Scraping status tracking per item

---

### 5. Admin Interface

**Dashboard**

- Real-time statistics overview
- Source counts by status (active, paused, failed)
- Recent activity feed (latest fetches and scrapes)
- Quick action buttons for common tasks
- Health metrics at a glance
- Links to job monitoring (Mission Control)

**Source Management Views**

- Table listing with status indicators
- Detailed source page with all settings
- Create/edit forms with validation
- Fetch history display per source
- Items list per source
- Scraping configuration panel
- Manual fetch/scrape triggers

**Item Browser**

- Paginated item listing across all sources
- Filter items by source
- Search by title
- Sort by publication date
- Item detail view with all content versions
- Display feed content, scraped HTML, and extracted content
- Scraping status indicators
- Manual scrape buttons

**Log Viewers**

- Fetch logs with success/failure indicators
- Scrape logs with adapter information
- Chronological activity timeline
- Error message display with full backtraces
- Performance metrics (duration, size)
- Filter logs by success/failure
- Detailed log view with all metadata

---

### 6. Background Job Processing

**Solid Queue Integration**

- Rails 8 native background processing
- Configurable queue priorities
- Job retry with exponential backoff
- Advisory locks for concurrent fetch prevention
- Job status tracking in UI
- Mission Control dashboard integration

**Job Types**

- **FetchFeedJob**: Fetch and process feed sources
- **ScrapeItemJob**: Extract full article content
- **SchedulerJob**: Find and enqueue due sources (optional)
- **ItemCleanupJob**: Remove old items per retention policy
- **LogCleanupJob**: Clean up old fetch/scrape logs

**Job Features**

- Idempotent job design
- Error handling with structured logging
- Automatic retry on transient failures
- Circuit breaker for persistent failures
- Performance tracking per job
- Callback hooks after job completion

---

### 7. Scheduling System

**Flexible Scheduler Architecture**

- Single entry point: `Scheduler.run`
- Invokable via rake task, cron, or systemd timer
- Optional recurring job via Solid Queue
- Manual trigger from dashboard
- Database-level locking for distributed environments

**Scheduling Strategies**

- **Fixed Interval**: Fetch every N hours
- **Adaptive**: Adjust based on posting frequency
- **Exponential Backoff**: Increase interval after failures
- **Jitter**: Random delays to distribute load
- **Backoff Until**: Honor temporary suspension times

**Source Scheduling**

- Per-source next_fetch_at timestamps
- Due source query with indexed lookups
- Configurable fetch interval per source
- Pause/resume affects scheduling
- Manual override via UI

---

### 8. Real-time Updates

**Turbo Streams**

- Live dashboard updates without polling
- Real-time item count updates
- Fetch status changes broadcast instantly
- New item notifications
- Log streaming to UI
- Job completion notifications

**Progressive Enhancement**

- Turbo Drive for fast page transitions
- Turbo Frames for isolated updates
- Stimulus controllers for interactivity
- Graceful degradation without JavaScript
- No WebSocket configuration required (Rails 8 default)

**Interactive UI Components**

- Auto-refresh dashboard
- Infinite scroll for item lists
- Toggle switches for source settings
- Loading states for async actions
- Toast notifications for feedback

---

### 9. Data Management

**Retention Policies**

- Configurable retention by age (days)
- Retention by maximum item count per source
- Global and per-source retention settings
- Soft delete option for items
- Cascade delete for source removal

**Cleanup Automation**

- Scheduled cleanup jobs via Solid Queue
- Manual cleanup via rake tasks
- Log retention separate from items
- Orphaned data cleanup
- Performance-optimized bulk deletes

**Data Integrity**

- Foreign key constraints
- Unique constraints on GUID and fingerprint
- Database-level validations
- Transaction support for atomic operations
- Counter cache consistency

---

### 10. Observability

**ActiveSupport Notifications**

- `source_monitor.fetch.start` - Before fetch begins
- `source_monitor.fetch.finish` - After fetch completes
- `source_monitor.scrape.start` - Before scraping
- `source_monitor.scrape.finish` - After scraping
- Custom event support for host apps

**Health Monitoring**

- `/health` endpoint with system status
- Database connection checks
- Job queue health monitoring
- Source health aggregation
- Performance metrics collection

**Logging**

- Structured fetch logs with full metadata
- Scrape logs with adapter details
- Error capture with backtraces
- HTTP response headers storage
- Duration tracking for all operations
- Success/failure statistics

**Metrics & Analytics**

- Fetch success/failure rates over time
- Scraping performance metrics
- Job queue depth monitoring
- Error pattern analysis
- Time-series data with Chart.js
- Exportable metrics data

---

### 11. Error Recovery

**Smart Retry Logic**

- Per-error-type retry strategies
- Exponential backoff with jitter
- Maximum retry limits
- Circuit breaker pattern
- Automatic interval adjustment on failure

**Self-Healing Features**

- Auto-pause failing sources
- Auto-recovery detection
- Backoff period enforcement
- Failure count tracking
- Manual retry from UI

**Error Tracking**

- Structured error class hierarchy
- Full error messages and backtraces
- Error timestamps and context
- Integration points for error tracking services
- Alert threshold configuration

**Alerting System**

- Configurable alert thresholds
- Webhook notification support
- Error tracking service integration
- Alert management UI
- Per-source alert configuration

---

### 12. Host Application Integration

**Configuration DSL**

```ruby
SourceMonitor.configure do |config|
  config.fetch_timeout = 30
  config.scrape_timeout = 60
  config.user_agent = "MyApp Bot"
  config.default_fetch_interval = 6
  config.retention_days = 30
end
```

**Event Callbacks**

- `after_item_created` - Process new items
- `after_item_scraped` - Handle scraped content
- `after_fetch_completed` - React to fetch events
- Custom item processors
- Integration with host app workflows

**Model Extensions**

- Override model methods via concerns
- Add custom validations
- Extend with STI for source types
- Custom scopes and queries
- Add polymorphic associations

**Custom Fields**

- Use metadata JSONB for custom data
- Table name prefixing support
- Migration generation for custom columns
- Flexible schema extensions

---

### 13. Performance & Scalability

**Database Optimization**

- Strategic indexing on all queries
- Counter cache for item counts
- Efficient pagination with Kaminari/Pagy
- N+1 query elimination
- Batch insert operations
- Query performance monitoring

**Caching Strategy**

- Solid Cache for Rails 8
- Fragment caching for expensive views
- Dashboard statistics caching
- Feed response caching with TTL
- Cache invalidation on updates

**Concurrent Processing**

- Parallel source fetching
- Advisory locks prevent duplicate work
- SELECT FOR UPDATE SKIP LOCKED
- Job queue prioritization
- Batch operations for efficiency

**Scalability Features**

- Horizontal scaling support
- Distributed job processing
- Database connection pooling
- Efficient memory usage
- Tested with 1000+ sources

---

### 14. Security

**Input Validation**

- URL validation and normalization
- HTML sanitization
- SQL injection prevention via ActiveRecord
- CSRF protection (Rails default)
- Mass assignment protection

**SSRF Protection**

- Private IP range blocking
- Allowlist/denylist support
- Request timeout enforcement
- Redirect limit enforcement
- SSL/TLS verification required

**Authentication & Authorization**

- Host app authentication integration
- Before action filters for access control
- Role-based permissions support
- API token authentication support
- Configurable authorization callbacks

**Security Headers**

- Content Security Policy
- X-Frame-Options
- X-Content-Type-Options
- Strict-Transport-Security
- Security audit via Brakeman

---

### 15. Installation & Setup

**Generator Tasks**

- One-command installation
- Automatic migration generation
- Route mounting with configuration
- Initializer creation
- Tailwind CSS setup
- Solid Queue configuration

**Configuration Options**

- Mount path customization
- Namespace isolation
- Custom controller inheritance
- Layout customization
- Helper method configuration

**Example Applications**

- Basic integration example
- Advanced customization example
- Custom adapter example
- Docker deployment configuration
- Production deployment guides

---

## Data Models

### Source

Complete feed source configuration and state tracking.

**Key Fields:**

- Feed URL, website URL, name
- Active status, fetch interval, next fetch time
- HTTP caching (ETag, Last-Modified)
- Error tracking (failure count, last error, backoff)
- Scraping settings (enabled, auto-scrape, adapter, custom CSS)
- Retention policies (days, max items)
- Custom headers, metadata (JSONB)

### Item

Aggregated content with multiple storage layers.

**Key Fields:**

- GUID, content fingerprint
- Title, URL, canonical URL
- Author(s), publication timestamps
- Summary, full content (from feed)
- Scraped HTML, extracted content
- Scraping status and timestamp
- Categories, tags, keywords (JSONB)
- Media enclosures, thumbnails (JSONB)
- Comments URL/count, metadata (JSONB)

### FetchLog

Complete audit trail of fetch operations.

**Key Fields:**

- Success/failure status
- Items created/updated/failed counts
- HTTP status, response headers (JSONB)
- Duration, feed size, items in feed
- Error class, message, backtrace
- Job ID, timestamps

### ScrapeLog

Audit trail of scraping operations.

**Key Fields:**

- Success/failure status
- Scraper adapter used
- HTTP status, duration, content length
- Error class, message
- Metadata (JSONB)

---

## Extension Points

### Custom Scrapers

Implement the `Scrapers::Base` interface to add new extraction methods:

- Custom HTML parsing logic
- JavaScript rendering support
- API-based content retrieval
- Specialized content extraction

### Event Handlers

Hook into the feed lifecycle:

- Send items to external systems
- Trigger notifications
- Update search indexes
- Generate summaries with AI
- Content classification

### Custom Processing

Extend item processing:

- Content transformation
- Metadata enrichment
- Categorization/tagging
- Spam filtering
- Quality scoring

### UI Customization

Modify the admin interface:

- Custom layouts and styling
- Additional views and actions
- Integration with host app navigation
- White-label branding
- Stimulus controllers ship as ES modules via Importmap (`source_monitor/application`); host apps can override controller registrations with `importmap.rb`
- Dropdown interactions use `stimulus-use` transitions when available and automatically fall back to class toggling when the module is not pinned
- `bin/rails app:source_monitor:assets:build` and `app:source_monitor:assets:verify` keep Tailwind builds current; verification runs before `rails test`

---

## Testing Support

### Test Infrastructure

- MiniTest configuration
- VCR cassettes for HTTP mocking
- WebMock for request stubbing
- System tests with Capybara
- Factory support for test data

### Test Coverage

- Unit tests for all services
- Integration tests for workflows
- System tests for UI interactions
- Contract tests for adapters
- Performance benchmarks

### Edge Cases

- Malformed feed handling
- Missing GUID scenarios
- Invalid date parsing
- Network timeout simulation
- Concurrent access tests

---

## Production Readiness

### Deployment Support

- Docker configuration
- Environment variable configuration
- Database migration management
- Background worker setup
- Monitoring integration

### Operational Features

- Health check endpoints
- Metrics collection
- Log aggregation support
- Error tracking integration
- Performance monitoring

### Documentation

- Comprehensive README
- Installation guide
- Configuration reference
- API documentation
- Troubleshooting guide
- Deployment best practices

### Release Strategy

- **Semantic Versioning**: Follow MAJOR.MINOR.PATCH. Breaking changes bump MAJOR, additive features bump MINOR, bugfixes and documentation-only changes bump PATCH.
- **Release Cadence**: Target monthly MINOR releases with PATCH releases on demand for urgent fixes.
- **Release Checklist**:
  1. `rbenv exec bundle exec rails test`
  2. `rbenv exec bundle exec rubocop`
  3. `rbenv exec bundle exec rake app:source_monitor:assets:verify`
  4. `rbenv exec bundle exec gem build source_monitor.gemspec`
  5. Update `CHANGELOG.md` with release notes and tag commit (`git tag vX.Y.Z`)
  6. Push tag and publish gem (`rbenv exec gem push pkg/source_monitor-X.Y.Z.gem`)
  7. Announce release in project README/CHANGELOG summary as needed

---

## Use Cases

**Content Aggregation**

- News aggregation platforms
- Blog aggregators
- Podcast directories
- Video feed aggregation
- Multi-source content hubs

**Monitoring & Tracking**

- Competitor content monitoring
- Brand mention tracking
- Industry news monitoring
- Topic-specific content tracking
- Research feed aggregation

**Content Processing**

- Feed-to-email newsletters
- Social media auto-posting
- Content curation systems
- Search index population
- ML training data collection

**Internal Tools**

- Company blog aggregation
- Team knowledge bases
- Documentation aggregation
- Product update tracking
- Industry research dashboards

---

## Getting Started

1. Add to Gemfile: `gem 'source_monitor'`
2. Run: `rails g source_monitor:install`
3. Run: `rails db:migrate`
4. Mount in routes: `mount SourceMonitor::Engine => "/source_monitor"`
5. Visit: `http://localhost:3000/source_monitor`
6. Add your first source and click "Fetch Now"

The engine is production-ready from day one with sensible defaults and can be customized extensively for specific needs.
