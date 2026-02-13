# frozen_string_literal: true

begin
  require "solid_queue"
rescue LoadError
  # Solid Queue is optional if the host app supplies a different Active Job backend.
end

begin
  require "solid_cable"
rescue LoadError
  # Solid Cable is optional if the host app uses Redis or another Action Cable adapter.
end

begin
  require "turbo-rails"
rescue LoadError
  # Turbo is optional but recommended for real-time updates.
end

begin
  require "ransack"
rescue LoadError
  # Ransack powers search forms when available.
end

require "source_monitor/version"
require "active_support/core_ext/module/redefine_method"

SourceMonitor.singleton_class.redefine_method(:table_name_prefix) do
  SourceMonitor::Engine.table_name_prefix
end

ActiveSupport.on_load(:active_record) do
  SourceMonitor.singleton_class.redefine_method(:table_name_prefix) do
    SourceMonitor::Engine.table_name_prefix
  end
end

require "source_monitor/engine"
require "source_monitor/configuration"
require "source_monitor/model_extensions"
require "source_monitor/events"
require "source_monitor/instrumentation"
require "source_monitor/metrics"
require "source_monitor/health"
require "source_monitor/realtime"
require "source_monitor/feedjira_extensions"

module SourceMonitor
  autoload :HTTP, "source_monitor/http"
  autoload :Scheduler, "source_monitor/scheduler"
  autoload :Assets, "source_monitor/assets"

  module Analytics
    autoload :SourceFetchIntervalDistribution, "source_monitor/analytics/source_fetch_interval_distribution"
    autoload :SourceActivityRates, "source_monitor/analytics/source_activity_rates"
    autoload :SourcesIndexMetrics, "source_monitor/analytics/sources_index_metrics"
  end

  module Dashboard
    autoload :QuickAction, "source_monitor/dashboard/quick_action"
    autoload :RecentActivity, "source_monitor/dashboard/recent_activity"
    autoload :RecentActivityPresenter, "source_monitor/dashboard/recent_activity_presenter"
    autoload :QuickActionsPresenter, "source_monitor/dashboard/quick_actions_presenter"
    autoload :Queries, "source_monitor/dashboard/queries"
    autoload :TurboBroadcaster, "source_monitor/dashboard/turbo_broadcaster"
    autoload :UpcomingFetchSchedule, "source_monitor/dashboard/upcoming_fetch_schedule"
  end

  module Fetching
    autoload :FetchError, "source_monitor/fetching/fetch_error"
    autoload :TimeoutError, "source_monitor/fetching/fetch_error"
    autoload :ConnectionError, "source_monitor/fetching/fetch_error"
    autoload :HTTPError, "source_monitor/fetching/fetch_error"
    autoload :ParsingError, "source_monitor/fetching/fetch_error"
    autoload :UnexpectedResponseError, "source_monitor/fetching/fetch_error"
    autoload :FeedFetcher, "source_monitor/fetching/feed_fetcher"
    autoload :FetchRunner, "source_monitor/fetching/fetch_runner"
    autoload :RetryPolicy, "source_monitor/fetching/retry_policy"
    autoload :StalledFetchReconciler, "source_monitor/fetching/stalled_fetch_reconciler"
    autoload :AdvisoryLock, "source_monitor/fetching/advisory_lock"
  end

  module ImportSessions
    autoload :EntryNormalizer, "source_monitor/import_sessions/entry_normalizer"
    autoload :HealthCheckBroadcaster, "source_monitor/import_sessions/health_check_broadcaster"
  end

  module Images
    autoload :ContentRewriter, "source_monitor/images/content_rewriter"
    autoload :Downloader, "source_monitor/images/downloader"
  end

  module Items
    autoload :ItemCreator, "source_monitor/items/item_creator"
    autoload :RetentionPruner, "source_monitor/items/retention_pruner"
    autoload :RetentionStrategies, "source_monitor/items/retention_strategies"
  end

  module Jobs
    autoload :CleanupOptions, "source_monitor/jobs/cleanup_options"
    autoload :Visibility, "source_monitor/jobs/visibility"
    autoload :SolidQueueMetrics, "source_monitor/jobs/solid_queue_metrics"
    autoload :FetchFailureCallbacks, "source_monitor/jobs/fetch_failure_subscriber"
    autoload :FetchFailureSubscriber, "source_monitor/jobs/fetch_failure_subscriber"
  end

  module Logs
    autoload :EntrySync, "source_monitor/logs/entry_sync"
    autoload :FilterSet, "source_monitor/logs/filter_set"
    autoload :Query, "source_monitor/logs/query"
    autoload :TablePresenter, "source_monitor/logs/table_presenter"
  end

  module Models
    autoload :Sanitizable, "source_monitor/models/sanitizable"
    autoload :UrlNormalizable, "source_monitor/models/url_normalizable"
  end

  module Pagination
    autoload :Paginator, "source_monitor/pagination/paginator"
  end

  module Release
    autoload :Changelog, "source_monitor/release/changelog"
    autoload :Runner, "source_monitor/release/runner"
  end

  module Scrapers
    autoload :Base, "source_monitor/scrapers/base"
    autoload :Readability, "source_monitor/scrapers/readability"

    module Fetchers
      autoload :HttpFetcher, "source_monitor/scrapers/fetchers/http_fetcher"
    end

    module Parsers
      autoload :ReadabilityParser, "source_monitor/scrapers/parsers/readability_parser"
    end
  end

  module Scraping
    autoload :Enqueuer, "source_monitor/scraping/enqueuer"
    autoload :BulkSourceScraper, "source_monitor/scraping/bulk_source_scraper"
    autoload :BulkResultPresenter, "source_monitor/scraping/bulk_result_presenter"
    autoload :State, "source_monitor/scraping/state"
    autoload :Scheduler, "source_monitor/scraping/scheduler"
    autoload :ItemScraper, "source_monitor/scraping/item_scraper"
  end

  module Security
    autoload :ParameterSanitizer, "source_monitor/security/parameter_sanitizer"
    autoload :Authentication, "source_monitor/security/authentication"
  end

  module Setup
    autoload :Requirements, "source_monitor/setup/requirements"
    autoload :ShellRunner, "source_monitor/setup/shell_runner"
    autoload :Detectors, "source_monitor/setup/detectors"
    autoload :DependencyChecker, "source_monitor/setup/dependency_checker"
    autoload :Prompter, "source_monitor/setup/prompter"
    autoload :GemfileEditor, "source_monitor/setup/gemfile_editor"
    autoload :BundleInstaller, "source_monitor/setup/bundle_installer"
    autoload :NodeInstaller, "source_monitor/setup/node_installer"
    autoload :InstallGenerator, "source_monitor/setup/install_generator"
    autoload :MigrationInstaller, "source_monitor/setup/migration_installer"
    autoload :InitializerPatcher, "source_monitor/setup/initializer_patcher"
    autoload :ProcfilePatcher, "source_monitor/setup/procfile_patcher"
    autoload :QueueConfigPatcher, "source_monitor/setup/queue_config_patcher"
    autoload :Workflow, "source_monitor/setup/workflow"
    autoload :UpgradeCommand, "source_monitor/setup/upgrade_command"
    autoload :CLI, "source_monitor/setup/cli"

    module Verification
      autoload :Result, "source_monitor/setup/verification/result"
      autoload :Summary, "source_monitor/setup/verification/result"
      autoload :PendingMigrationsVerifier, "source_monitor/setup/verification/pending_migrations_verifier"
      autoload :SolidQueueVerifier, "source_monitor/setup/verification/solid_queue_verifier"
      autoload :ActionCableVerifier, "source_monitor/setup/verification/action_cable_verifier"
      autoload :RecurringScheduleVerifier, "source_monitor/setup/verification/recurring_schedule_verifier"
      autoload :Runner, "source_monitor/setup/verification/runner"
      autoload :Printer, "source_monitor/setup/verification/printer"
      autoload :TelemetryLogger, "source_monitor/setup/verification/telemetry_logger"
    end
  end

  module Sources
    autoload :Params, "source_monitor/sources/params"
    autoload :TurboStreamPresenter, "source_monitor/sources/turbo_stream_presenter"
  end

  module TurboStreams
    autoload :StreamResponder, "source_monitor/turbo_streams/stream_responder"
  end

  class << self
    def configure
      yield config
      config.check_deprecations!
      SourceMonitor::ModelExtensions.reload!
    end

    def config
      @config ||= Configuration.new
    end

    def events
      config.events
    end

    def reset_configuration!
      @config = Configuration.new
      SourceMonitor::ModelExtensions.reload!
      SourceMonitor::Health.setup!
      SourceMonitor::Realtime.setup!
      SourceMonitor::Dashboard::TurboBroadcaster.setup!
    end

    def queue_name(role)
      config.queue_name_for(role)
    end

    def queue_concurrency(role)
      config.concurrency_for(role)
    end

    def table_name_prefix
      SourceMonitor::Engine.table_name_prefix
    end

    def mission_control_enabled?
      config.mission_control_enabled
    end

    def mission_control_dashboard_path
      raw_path = config.mission_control_dashboard_path
      resolved = resolve_callable(raw_path)
      return if resolved.blank?

      valid_dashboard_path?(resolved) ? resolved : nil
    rescue StandardError
      nil
    end

    private

    def resolve_callable(value)
      value.respond_to?(:call) ? value.call : value
    end

    def valid_dashboard_path?(value)
      return true if value.to_s.match?(%r{\Ahttps?://})

      Rails.application.routes.recognize_path(value, method: :get)
      true
    rescue ActionController::RoutingError
      false
    end
  end
end
