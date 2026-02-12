# frozen_string_literal: true

module SourceMonitor
  module Logs
    class TablePresenter
      class Row
        def initialize(entry, url_helpers)
          @entry = entry
          @url_helpers = url_helpers
        end

        def dom_id
          "#{type_slug}-#{entry.loggable_id}"
        end

        def type_label
          if fetch?
            "Fetch"
          elsif scrape?
            "Scrape"
          else
            "Health Check"
          end
        end

        def type_variant
          if fetch?
            :fetch
          elsif scrape?
            :scrape
          else
            :health_check
          end
        end

        def status_label
          entry.success? ? "Success" : "Failure"
        end

        def status_variant
          entry.success? ? :success : :failure
        end

        def started_at
          entry.started_at
        end

        def primary_label
          if scrape?
            entry.item&.title.presence || "(untitled)"
          else
            entry.source&.name
          end
        end

        def primary_path
          if scrape? && entry.item
            url_helpers.item_path(entry.item)
          elsif entry.source
            url_helpers.source_path(entry.source)
          end
        end

        def url_label
          if fetch?
            domain_from_feed_url
          elsif scrape?
            entry.item&.url
          end
        end

        def url_href
          if fetch?
            entry.source&.feed_url
          elsif scrape?
            entry.item&.url
          end
        end

        def source_label
          entry.source&.name
        end

        def source_path
          url_helpers.source_path(entry.source) if entry.source
        end

        def http_summary
          if fetch?
            entry.http_status.present? ? entry.http_status.to_s : "—"
          elsif scrape?
            parts = []
            parts << entry.http_status.to_s if entry.http_status
            parts << entry.scraper_adapter if entry.scraper_adapter.present?
            parts.compact.join(" · ").presence || "—"
          else
            entry.http_status.present? ? entry.http_status.to_s : "—"
          end
        end

        def metrics_summary
          if fetch?
            "+#{entry.items_created.to_i} / ~#{entry.items_updated.to_i} / ✕#{entry.items_failed.to_i}"
          else
            entry.duration_ms.present? ? "#{entry.duration_ms} ms" : "—"
          end
        end

        def detail_path
          case entry.loggable
          when SourceMonitor::FetchLog
            url_helpers.fetch_log_path(entry.loggable)
          when SourceMonitor::ScrapeLog
            url_helpers.scrape_log_path(entry.loggable)
          else
            nil
          end
        end

        def adapter
          entry.scraper_adapter
        end

        def success?
          entry.success?
        end

        def failure?
          !success?
        end

        def error_message
          entry.error_message
        end

        def type_slug
          if fetch?
            "fetch"
          elsif scrape?
            "scrape"
          else
            "health-check"
          end
        end

        def fetch?
          entry.fetch?
        end

        def scrape?
          entry.scrape?
        end

        def health_check?
          entry.health_check?
        end

        private

        attr_reader :entry, :url_helpers

        def domain_from_feed_url
          feed_url = entry.source&.feed_url
          return nil if feed_url.blank?

          URI.parse(feed_url.to_s).host
        rescue URI::InvalidURIError
          nil
        end
      end

      def initialize(entries:, url_helpers:)
        @entries = entries
        @url_helpers = url_helpers
      end

      def rows
        entries.map { |entry| Row.new(entry, url_helpers) }
      end

      private

      attr_reader :entries, :url_helpers
    end
  end
end
