# frozen_string_literal: true

require "active_support/notifications"
require "source_monitor/dashboard/upcoming_fetch_schedule"
require "source_monitor/dashboard/queries/stats_query"
require "source_monitor/dashboard/queries/recent_activity_query"

module SourceMonitor
  module Dashboard
    class Queries
      def initialize(reference_time: Time.current)
        @reference_time = reference_time
        @cache = Cache.new
      end

      def stats
        cache.fetch(:stats) do
          measure(:stats) do
            StatsQuery.new(reference_time:).call
          end
        end
      end

      def recent_activity(limit: DEFAULT_RECENT_ACTIVITY_LIMIT)
        cache.fetch([ :recent_activity, limit ]) do
          measure(:recent_activity, limit:) do
            RecentActivityQuery.new(limit:).call
          end
        end
      end

      def quick_actions
        QUICK_ACTIONS
      end

      def job_metrics(queue_names: queue_name_map.values)
        measure(:job_metrics, queue_names:) do
          summaries = SourceMonitor::Jobs::SolidQueueMetrics.call(queue_names:)

          queue_name_map.map do |role, queue_name|
            summary = summaries[queue_name.to_s] || SourceMonitor::Jobs::SolidQueueMetrics::QueueSummary.new(
              queue_name: queue_name.to_s,
              ready_count: 0,
              scheduled_count: 0,
              failed_count: 0,
              recurring_count: 0,
              paused: false,
              last_enqueued_at: nil,
              last_started_at: nil,
              last_finished_at: nil,
              available: false
            )

            {
              role: role,
              queue_name: queue_name,
              summary: summary
            }
          end
        end
      end

      def upcoming_fetch_schedule
        cache.fetch(:upcoming_fetch_schedule) do
          measure(:upcoming_fetch_schedule) do
            SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.active)
          end
        end
      end

      private

      DEFAULT_RECENT_ACTIVITY_LIMIT = 8

      attr_reader :reference_time, :cache

      def measure(name, metadata = {})
        started_at = monotonic_time
        result = yield
        duration_ms = ((monotonic_time - started_at) * 1000.0).round(2)
        recorded_at = Time.current

        payload = metadata.merge(duration_ms:, recorded_at:)
        ActiveSupport::Notifications.instrument("source_monitor.dashboard.#{name}", payload)
        record_metrics(name, result, duration_ms:, recorded_at:, metadata:)

        result
      end

      def record_metrics(name, result, duration_ms:, recorded_at:, metadata:)
        SourceMonitor::Metrics.gauge(:"dashboard_#{name}_duration_ms", duration_ms)
        SourceMonitor::Metrics.gauge(:"dashboard_#{name}_last_run_at_epoch", recorded_at.to_f)

        case name
        when :stats
          record_stats_metrics(result)
        when :recent_activity
          SourceMonitor::Metrics.gauge(:dashboard_recent_activity_events_count, result.size)
          SourceMonitor::Metrics.gauge(:dashboard_recent_activity_limit, metadata[:limit]) if metadata[:limit]
        when :job_metrics
          SourceMonitor::Metrics.gauge(:dashboard_job_metrics_queue_count, result.size)
        when :upcoming_fetch_schedule
          SourceMonitor::Metrics.gauge(:dashboard_fetch_schedule_group_count, result.groups.size)
        end
      end

      def record_stats_metrics(stats)
        SourceMonitor::Metrics.gauge(:dashboard_stats_total_sources, stats[:total_sources])
        SourceMonitor::Metrics.gauge(:dashboard_stats_active_sources, stats[:active_sources])
        SourceMonitor::Metrics.gauge(:dashboard_stats_failed_sources, stats[:failed_sources])
        SourceMonitor::Metrics.gauge(:dashboard_stats_total_items, stats[:total_items])
        SourceMonitor::Metrics.gauge(:dashboard_stats_fetches_today, stats[:fetches_today])
      end

      def queue_name_map
        @queue_name_map ||= {
          fetch: SourceMonitor.queue_name(:fetch),
          scrape: SourceMonitor.queue_name(:scrape)
        }
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      class Cache
        def initialize
          @store = {}
        end

        def fetch(key)
          if store.key?(key)
            store.fetch(key)
          else
            store[key] = yield
          end
        end

        private

        attr_reader :store
      end

      QUICK_ACTIONS = [
        SourceMonitor::Dashboard::QuickAction.new(
          label: "Add Source",
          description: "Create a new feed source",
          route_name: :new_source_path
        ).freeze,
        SourceMonitor::Dashboard::QuickAction.new(
          label: "View Sources",
          description: "Manage existing sources",
          route_name: :sources_path
        ).freeze,
        SourceMonitor::Dashboard::QuickAction.new(
          label: "Check Health",
          description: "Verify engine status",
          route_name: :health_path
        ).freeze
      ].freeze
    end
  end
end
