# Initializer Template Reference

Complete annotated initializer for `config/initializers/source_monitor.rb`.

The install generator creates this file from `lib/generators/source_monitor/install/templates/source_monitor.rb.tt`. This reference expands on every option.

## Full Template

```ruby
# frozen_string_literal: true

# SourceMonitor engine configuration.
#
# These values default to conservative settings that work for most hosts.
# Tweak them here instead of monkey-patching the engine so upgrades remain easy.
# Restart the application after changes.
SourceMonitor.configure do |config|

  # ===========================================================================
  # Queue & Worker Settings
  # ===========================================================================

  # Namespace prefix for queue names and instrumentation keys.
  # Combined with ActiveJob.queue_name_prefix automatically.
  config.queue_namespace = "source_monitor"

  # Dedicated queue names. Must match entries in config/solid_queue.yml.
  config.fetch_queue_name = "source_monitor_fetch"
  config.scrape_queue_name = "source_monitor_scrape"
  config.maintenance_queue_name = "source_monitor_maintenance"

  # Worker concurrency per queue (advisory for Solid Queue).
  config.fetch_queue_concurrency = 2
  config.scrape_queue_concurrency = 2
  config.maintenance_queue_concurrency = 1

  # Override the job class Solid Queue uses for recurring "command" tasks.
  # config.recurring_command_job_class = "MyRecurringCommandJob"

  # Toggle lightweight queue metrics on the dashboard.
  config.job_metrics_enabled = true

  # ===========================================================================
  # Mission Control Integration
  # ===========================================================================

  # Show "Open Mission Control" link on the SourceMonitor dashboard.
  config.mission_control_enabled = false

  # String path, route helper lambda, or nil.
  # config.mission_control_dashboard_path = "/mission_control"
  # config.mission_control_dashboard_path = -> {
  #   Rails.application.routes.url_helpers.mission_control_jobs_path
  # }
  config.mission_control_dashboard_path = nil

  # ===========================================================================
  # Authentication
  # ===========================================================================
  # Handlers: Symbol (invoked on controller) or callable (receives controller).

  # Authenticate before accessing any SourceMonitor page.
  # config.authentication.authenticate_with :authenticate_user!

  # Authorize after authentication (return false or raise to deny).
  # config.authentication.authorize_with ->(controller) {
  #   controller.current_user&.admin?
  # }

  # Method names SourceMonitor uses to access current user info.
  # config.authentication.current_user_method = :current_user
  # config.authentication.user_signed_in_method = :user_signed_in?

  # ===========================================================================
  # HTTP Client
  # ===========================================================================
  # Maps to Faraday middleware options.

  config.http.timeout = 15          # Total request timeout (seconds)
  config.http.open_timeout = 5      # Connection open timeout (seconds)
  config.http.max_redirects = 5     # Max redirects to follow
  # config.http.user_agent = "SourceMonitor/#{SourceMonitor::VERSION}"
  # config.http.proxy = ENV["SOURCE_MONITOR_HTTP_PROXY"]
  # config.http.headers = { "X-Request-ID" => -> { SecureRandom.uuid } }

  # Retry settings (mapped to faraday-retry)
  # config.http.retry_max = 4
  # config.http.retry_interval = 0.5
  # config.http.retry_interval_randomness = 0.5
  # config.http.retry_backoff_factor = 2
  # config.http.retry_statuses = [429, 500, 502, 503, 504]

  # ===========================================================================
  # Adaptive Fetch Scheduling
  # ===========================================================================

  # config.fetching.min_interval_minutes = 5       # Floor (default: 5 min)
  # config.fetching.max_interval_minutes = 1440    # Ceiling (default: 24 hrs)
  # config.fetching.increase_factor = 1.25         # Multiplier when no new items
  # config.fetching.decrease_factor = 0.75         # Multiplier when items arrive
  # config.fetching.failure_increase_factor = 1.5  # Multiplier on errors
  # config.fetching.jitter_percent = 0.1           # Random jitter (+/-10%)
  # config.fetching.scheduler_batch_size = 25      # Max sources per scheduler run
  # config.fetching.stale_timeout_minutes = 5      # Minutes before stuck fetch is reset

  # ===========================================================================
  # Source Health Monitoring
  # ===========================================================================

  config.health.window_size = 20                   # Fetch attempts to evaluate
  config.health.healthy_threshold = 0.8            # Ratio for "healthy" badge
  config.health.warning_threshold = 0.5            # Ratio for "warning" badge
  config.health.auto_pause_threshold = 0.2         # Auto-pause below this
  config.health.auto_resume_threshold = 0.6        # Auto-resume above this
  config.health.auto_pause_cooldown_minutes = 60   # Grace period before re-enable

  # ===========================================================================
  # Scraper Adapters
  # ===========================================================================
  # Must inherit from SourceMonitor::Scrapers::Base.

  # config.scrapers.register(:custom, "MyApp::Scrapers::CustomAdapter")
  # config.scrapers.unregister(:readability)  # Remove built-in

  # ===========================================================================
  # Retention Defaults
  # ===========================================================================
  # Sources inherit these when their retention fields are blank.

  config.retention.items_retention_days = nil   # nil = retain forever
  config.retention.max_items = nil              # nil = unlimited
  # config.retention.strategy = :destroy        # or :soft_delete

  # ===========================================================================
  # Scraping Controls
  # ===========================================================================

  # config.scraping.max_in_flight_per_source = 25  # Concurrent scrapes per source
  # config.scraping.max_bulk_batch_size = 100       # Max bulk enqueue size

  # ===========================================================================
  # Event Callbacks
  # ===========================================================================
  # Handlers receive a single event struct.

  # config.events.after_item_created do |event|
  #   # event.item, event.source, event.entry, event.result, event.status
  #   NewItemNotifier.publish(event.item, source: event.source)
  # end

  # config.events.after_item_scraped do |event|
  #   # event.item, event.source, event.result, event.log, event.status
  #   SearchIndexer.reindex(event.item) if event.success?
  # end

  # config.events.after_fetch_completed do |event|
  #   # event.source, event.result, event.status
  #   Rails.logger.info "Fetch for #{event.source.name}: #{event.status}"
  # end

  # config.events.register_item_processor ->(context) {
  #   # context.item, context.source, context.entry, context.result, context.status
  #   ItemIndexer.index(context.item)
  # }

  # ===========================================================================
  # Model Extensions
  # ===========================================================================

  # Override default table name prefix (default: "sourcemon_").
  # config.models.table_name_prefix = "sourcemon_"

  # Include concerns to extend engine models.
  # config.models.source.include_concern "MyApp::SourceMonitor::SourceExtensions"
  # config.models.item.include_concern "MyApp::SourceMonitor::ItemExtensions"

  # Register custom validations.
  # config.models.source.validate :enforce_custom_rules
  # config.models.source.validate ->(record) {
  #   record.errors.add(:base, "custom error") unless record.valid_for_my_app?
  # }

  # ===========================================================================
  # Favicons (Active Storage)
  # ===========================================================================
  # Automatically fetch and store source favicons via Active Storage.
  # Requires Active Storage in the host app (rails active_storage:install).
  # Without Active Storage, favicons are silently disabled -- colored
  # initials placeholders are shown instead.

  # config.favicons.enabled = true                    # default: true
  # config.favicons.fetch_timeout = 5                 # seconds
  # config.favicons.max_download_size = 1_048_576     # 1 MB
  # config.favicons.retry_cooldown_days = 7
  # config.favicons.allowed_content_types = %w[
  #   image/x-icon image/vnd.microsoft.icon image/png
  #   image/jpeg image/gif image/svg+xml image/webp
  # ]

  # ===========================================================================
  # Realtime (Action Cable) Adapter
  # ===========================================================================

  config.realtime.adapter = :solid_cable
  # config.realtime.adapter = :redis
  # config.realtime.redis_url = ENV.fetch("SOURCE_MONITOR_REDIS_URL", nil)

  # Solid Cable tuning:
  # config.realtime.solid_cable.polling_interval = "0.1.seconds"
  # config.realtime.solid_cable.message_retention = "1.day"
  # config.realtime.solid_cable.autotrim = true
  # config.realtime.solid_cable.silence_polling = true
  # config.realtime.solid_cable.use_skip_locked = true
  # config.realtime.solid_cable.connects_to = { database: { writing: :cable } }
end
```
