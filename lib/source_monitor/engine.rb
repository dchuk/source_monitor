# frozen_string_literal: true

module SourceMonitor
  class Engine < ::Rails::Engine
    isolate_namespace SourceMonitor
    require "source_monitor/assets/bundler"
    require "source_monitor/jobs/fetch_failure_subscriber"

    def self.table_name_prefix
      SourceMonitor.config.models.table_name_prefix
    end

    initializer "source_monitor.assets" do |app|
      next unless app.config.respond_to?(:assets)

      engine_root = SourceMonitor::Engine.root

      app.config.assets.paths << engine_root.join("app/assets/builds").to_s
      app.config.assets.paths << engine_root.join("app/assets/images").to_s
      app.config.assets.paths << engine_root.join("app/assets/svgs").to_s
    end

    initializer "source_monitor.assets.sprockets" do |app|
      next unless app.config.respond_to?(:assets)

      manifest_entry = "source_monitor_manifest.js"
      app.config.assets.precompile << manifest_entry unless app.config.assets.precompile.include?(manifest_entry)
      app.config.assets.precompile.concat(SourceMonitor::Engine.asset_precompile_entries)
      app.config.assets.precompile.uniq!
    end

    initializer "source_monitor.metrics" do
      SourceMonitor::Metrics.setup_subscribers!
    end

    initializer "source_monitor.dashboard_streams" do
      config.to_prepare do
        SourceMonitor::Health.setup!
        SourceMonitor::Realtime.setup!
        SourceMonitor::Dashboard::TurboBroadcaster.setup!
      end
    end

    initializer "source_monitor.jobs" do |app|
      SourceMonitor::Jobs::Visibility.setup!
      SourceMonitor::Jobs::FetchFailureSubscriber.setup!

      if defined?(::SolidQueue)
        adapter_name = ActiveJob::Base.queue_adapter_name.to_s
        if adapter_name.empty? || adapter_name == "async"
          ActiveJob::Base.queue_adapter = :solid_queue
        end

        if defined?(::SolidQueue::RecurringTask)
          job_class_config = SourceMonitor.config.recurring_command_job_class
          if job_class_config.present?
            resolved_class = job_class_config.is_a?(String) ? job_class_config.constantize : job_class_config
            SolidQueue::RecurringTask.default_job_class = resolved_class
          end
        end

        if defined?(MissionControl::Jobs)
          adapters = MissionControl::Jobs.adapters
          if adapters.respond_to?(:add)
            adapters.add(:solid_queue)
            adapters.delete(:async)
          elsif adapters.respond_to?(:<<)
            adapters << :solid_queue unless adapters.include?(:solid_queue)
            adapters.delete(:async) if adapters.respond_to?(:delete)
          end

          if defined?(ActiveJob::QueueAdapters::SolidQueueExt) &&
              !(ActiveJob::QueueAdapters::SolidQueueAdapter < ActiveJob::QueueAdapters::SolidQueueExt)
            ActiveJob::QueueAdapters::SolidQueueAdapter.prepend ActiveJob::QueueAdapters::SolidQueueExt
          end

          MissionControl::Jobs.applications.each do |application|
            next if application.servers.any? { |server| server.queue_adapter_name == :solid_queue }

            solid_queue_adapter = ActiveJob::QueueAdapters.lookup(:solid_queue).new
            application.add_servers(solid_queue: solid_queue_adapter)
          end
        end

        app.config.after_initialize do
          SourceMonitor::Jobs::Visibility.setup!
        end
      end
    end
    class << self
      def asset_precompile_entries
        engine_root = SourceMonitor::Engine.root
        asset_roots = {
          images: engine_root.join("app/assets/images"),
          svgs: engine_root.join("app/assets/svgs")
        }

        asset_roots.flat_map do |_, base_path|
          Dir[base_path.join("source_monitor/**/*").to_s].filter_map do |absolute_path|
            next unless File.file?(absolute_path)
            next if File.basename(absolute_path).start_with?(".")

            Pathname.new(absolute_path).relative_path_from(base_path).to_s
          end
        end
      end
    end
  end
end
