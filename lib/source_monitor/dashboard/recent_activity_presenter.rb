# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    class RecentActivityPresenter
      def initialize(events, url_helpers:)
        @events = events
        @url_helpers = url_helpers
      end

      def to_a
        events.map { |event| build_view_model(event) }
      end

      private

      attr_reader :events, :url_helpers

      def build_view_model(event)
        case event.type
        when :fetch_log
          fetch_event(event)
        when :scrape_log
          scrape_event(event)
        when :item
          item_event(event)
        else
          fallback_event(event)
        end
      end

      def fetch_event(event)
        domain = source_domain(event.source_feed_url)
        {
          label: "Fetch ##{event.id}",
          description: "#{event.items_created.to_i} created / #{event.items_updated.to_i} updated",
          status: event.success? ? :success : :failure,
          type: :fetch,
          time: event.occurred_at,
          path: url_helpers.fetch_log_path(event.id),
          url_display: domain,
          url_href: event.source_feed_url
        }
      end

      def scrape_event(event)
        {
          label: "Scrape ##{event.id}",
          description: (event.scraper_adapter.presence || "Scraper"),
          status: event.success? ? :success : :failure,
          type: :scrape,
          time: event.occurred_at,
          path: url_helpers.scrape_log_path(event.id),
          url_display: event.item_url,
          url_href: event.item_url
        }
      end

      def source_domain(feed_url)
        return nil if feed_url.blank?

        URI.parse(feed_url.to_s).host
      rescue URI::InvalidURIError
        nil
      end

      def item_event(event)
        {
          label: event.item_title.presence || "New Item",
          description: event.source_name.presence || event.item_url.presence || "New feed item",
          status: :success,
          type: :item,
          time: event.occurred_at,
          path: url_helpers.item_path(event.id)
        }
      end

      def fallback_event(event)
        {
          label: "Event ##{event.id}",
          description: event.source_name.presence || "No additional details recorded.",
          status: event.success? ? :success : :failure,
          type: event.type || :unknown,
          time: event.occurred_at,
          path: nil
        }
      end
    end
  end
end
