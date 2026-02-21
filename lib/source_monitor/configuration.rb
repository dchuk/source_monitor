# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require "source_monitor/configuration/http_settings"
require "source_monitor/configuration/fetching_settings"
require "source_monitor/configuration/health_settings"
require "source_monitor/configuration/scraping_settings"
require "source_monitor/configuration/realtime_settings"
require "source_monitor/configuration/retention_settings"
require "source_monitor/configuration/authentication_settings"
require "source_monitor/configuration/images_settings"
require "source_monitor/configuration/favicons_settings"
require "source_monitor/configuration/scraper_registry"
require "source_monitor/configuration/events"
require "source_monitor/configuration/validation_definition"
require "source_monitor/configuration/model_definition"
require "source_monitor/configuration/models"
require "source_monitor/configuration/deprecation_registry"

module SourceMonitor
  class Configuration
    attr_accessor :queue_namespace,
      :fetch_queue_name,
      :scrape_queue_name,
      :fetch_queue_concurrency,
      :scrape_queue_concurrency,
      :recurring_command_job_class,
      :job_metrics_enabled,
      :mission_control_enabled,
      :mission_control_dashboard_path

    attr_reader :http, :scrapers, :retention, :events, :models, :realtime, :fetching, :health, :authentication, :scraping, :images, :favicons

    DEFAULT_QUEUE_NAMESPACE = "source_monitor"

    def initialize
      @queue_namespace = DEFAULT_QUEUE_NAMESPACE
      @fetch_queue_name = "#{DEFAULT_QUEUE_NAMESPACE}_fetch"
      @scrape_queue_name = "#{DEFAULT_QUEUE_NAMESPACE}_scrape"
      @fetch_queue_concurrency = 2
      @scrape_queue_concurrency = 2
      @recurring_command_job_class = nil
      @job_metrics_enabled = true
      @mission_control_enabled = false
      @mission_control_dashboard_path = nil
      @http = HTTPSettings.new
      @scrapers = ScraperRegistry.new
      @retention = RetentionSettings.new
      @events = Events.new
      @models = Models.new
      @realtime = RealtimeSettings.new
      @fetching = FetchingSettings.new
      @health = HealthSettings.new
      @authentication = AuthenticationSettings.new
      @scraping = ScrapingSettings.new
      @images = ImagesSettings.new
      @favicons = FaviconsSettings.new
    end

    def queue_name_for(role)
      explicit_name =
        case role.to_sym
        when :fetch
          fetch_queue_name
        when :scrape
          scrape_queue_name
        else
          raise ArgumentError, "unknown queue role #{role.inspect}"
        end

      prefix = ActiveJob::Base.queue_name_prefix
      delimiter = ActiveJob::Base.queue_name_delimiter

      if prefix && !prefix.empty?
        [ prefix, explicit_name ].join(delimiter)
      else
        explicit_name
      end
    end

    def concurrency_for(role)
      case role.to_sym
      when :fetch
        fetch_queue_concurrency
      when :scrape
        scrape_queue_concurrency
      else
        raise ArgumentError, "unknown queue role #{role.inspect}"
      end
    end

    # Post-configure hook for deprecation validation.
    # Delegates to DeprecationRegistry.check_defaults! for future
    # "default changed" checks. Currently a no-op.
    def check_deprecations!
      DeprecationRegistry.check_defaults!(self)
    end
  end
end
