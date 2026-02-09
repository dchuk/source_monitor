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
require "source_monitor/http"
require "source_monitor/feedjira_extensions"
require "source_monitor/dashboard/quick_action"
require "source_monitor/dashboard/recent_activity"
require "source_monitor/dashboard/recent_activity_presenter"
require "source_monitor/dashboard/quick_actions_presenter"
require "source_monitor/dashboard/queries"
require "source_monitor/dashboard/turbo_broadcaster"
require "source_monitor/logs/entry_sync"
require "source_monitor/logs/filter_set"
require "source_monitor/logs/query"
require "source_monitor/logs/table_presenter"
require "source_monitor/realtime"
require "source_monitor/analytics/source_fetch_interval_distribution"
require "source_monitor/analytics/source_activity_rates"
require "source_monitor/analytics/sources_index_metrics"
require "source_monitor/jobs/cleanup_options"
require "source_monitor/jobs/visibility"
require "source_monitor/jobs/solid_queue_metrics"
require "source_monitor/security/parameter_sanitizer"
require "source_monitor/security/authentication"
require "source_monitor/pagination/paginator"
require "source_monitor/turbo_streams/stream_responder"
require "source_monitor/scrapers/base"
require "source_monitor/scrapers/fetchers/http_fetcher"
require "source_monitor/scrapers/parsers/readability_parser"
require "source_monitor/scrapers/readability"
require "source_monitor/scraping/enqueuer"
require "source_monitor/scraping/bulk_source_scraper"
require "source_monitor/scraping/state"
require "source_monitor/scraping/scheduler"
require "source_monitor/scraping/item_scraper"
require "source_monitor/fetching/fetch_error"
require "source_monitor/fetching/feed_fetcher"
require "source_monitor/items/retention_pruner"
require "source_monitor/fetching/fetch_runner"
require "source_monitor/scheduler"
require "source_monitor/items/item_creator"
require "source_monitor/health"
require "source_monitor/assets"
require "source_monitor/setup/requirements"
require "source_monitor/setup/shell_runner"
require "source_monitor/setup/detectors"
require "source_monitor/setup/dependency_checker"
require "source_monitor/setup/prompter"
require "source_monitor/setup/gemfile_editor"
require "source_monitor/setup/bundle_installer"
require "source_monitor/setup/node_installer"
require "source_monitor/setup/install_generator"
require "source_monitor/setup/migration_installer"
require "source_monitor/setup/initializer_patcher"
require "source_monitor/setup/verification/result"
require "source_monitor/setup/verification/solid_queue_verifier"
require "source_monitor/setup/verification/action_cable_verifier"
require "source_monitor/setup/verification/runner"
require "source_monitor/setup/verification/printer"
require "source_monitor/setup/verification/telemetry_logger"
require "source_monitor/setup/workflow"
require "source_monitor/setup/cli"

module SourceMonitor
  class << self
    def configure
      yield config
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
