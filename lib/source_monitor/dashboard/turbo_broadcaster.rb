# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    module TurboBroadcaster
      STREAM_NAME = "source_monitor_dashboard"

      module_function

      def setup!
        return unless turbo_streams_available?

        register_callback(:after_fetch_completed, fetch_callback)
        register_callback(:after_item_created, item_callback)
      end

      def fetch_callback
        @fetch_callback ||= lambda { |_event| broadcast_dashboard_updates }
      end

      def item_callback
        @item_callback ||= lambda { |_event| broadcast_dashboard_updates }
      end

      STAT_CARDS = [
        { key: "total_sources", label: "Sources", stat: :total_sources, caption: "Total registered" },
        { key: "active_sources", label: "Active", stat: :active_sources, caption: "Fetching on schedule" },
        { key: "failed_sources", label: "Failures", stat: :failed_sources, caption: "Require attention" },
        { key: "total_items", label: "Items", stat: :total_items, caption: "Stored entries" },
        { key: "fetches_today", label: "Fetches Today", stat: :fetches_today, caption: "Completed runs" }
      ].freeze

      def broadcast_dashboard_updates
        return unless turbo_streams_available?

        queries = SourceMonitor::Dashboard::Queries.new
        url_helpers = SourceMonitor::Engine.routes.url_helpers
        stats = queries.stats

        STAT_CARDS.each do |card|
          Turbo::StreamsChannel.broadcast_replace_to(
            STREAM_NAME,
            target: "source_monitor_stat_#{card[:key]}",
            html: render_partial("source_monitor/dashboard/stat_card", stat_card: {
              key: card[:key],
              label: card[:label],
              value: stats[card[:stat]],
              caption: card[:caption]
            })
          )
        end

        Turbo::StreamsChannel.broadcast_replace_to(
          STREAM_NAME,
          target: "source_monitor_dashboard_recent_activity",
          html: render_partial(
            "source_monitor/dashboard/recent_activity",
            recent_activity: SourceMonitor::Dashboard::RecentActivityPresenter.new(
              queries.recent_activity,
              url_helpers:
            ).to_a
          )
        )

        fetch_schedule = queries.upcoming_fetch_schedule
        Turbo::StreamsChannel.broadcast_replace_to(
          STREAM_NAME,
          target: "source_monitor_dashboard_fetch_schedule",
          html: render_partial(
            "source_monitor/dashboard/fetch_schedule",
            groups: fetch_schedule.groups,
            reference_time: fetch_schedule.reference_time
          )
        )
      rescue StandardError => error
        Rails.logger.error(
          "[SourceMonitor] Turbo stream broadcast failed: #{error.class}: #{error.message}"
        )
      end

      def turbo_streams_available?
        defined?(Turbo::StreamsChannel)
      end
      private_class_method :turbo_streams_available?

      def render_partial(partial, locals)
        SourceMonitor::DashboardController.render(
          partial:,
          locals:
        )
      end
      private_class_method :render_partial

      def register_callback(name, callback)
        callbacks = SourceMonitor.config.events.callbacks_for(name)
        return if callbacks.include?(callback)

        SourceMonitor.config.events.public_send(name, callback)
      end
      private_class_method :register_callback
    end
  end
end
