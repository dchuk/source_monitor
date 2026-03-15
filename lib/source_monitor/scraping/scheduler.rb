# frozen_string_literal: true

module SourceMonitor
  module Scraping
    # Identifies items that still need scraping and enqueue jobs for sources
    # configured for automatic scraping. This mirrors the feed fetch scheduler
    # so recurring tasks can keep the scrape queue warm.
    class Scheduler
      DEFAULT_BATCH_SIZE = 100

      def self.run(limit: DEFAULT_BATCH_SIZE)
        new(limit:).run
      end

      def initialize(limit:)
        @limit = limit
      end

      def run
        items = due_items.limit(limit).includes(:source).to_a
        return 0 if items.empty?

        items.sum do |item|
          result = SourceMonitor::Scraping::Enqueuer.enqueue(item: item, source: item.source, reason: :auto)
          result.enqueued? ? 1 : 0
        end
      rescue StandardError => error
        Rails.logger.warn(
          "[SourceMonitor::Scraping::Scheduler] Scheduler run failed: #{error.class} - #{error.message}"
        ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        0
      end

      private

      attr_reader :limit

      def due_items
        SourceMonitor::Item
          .joins(:source)
          .merge(SourceMonitor::Source.active.where(scraping_enabled: true, auto_scrape: true))
          .where(scraped_at: nil)
          .where(scrape_status: [ nil, "" ])
          .order(Arel.sql("sourcemon_items.created_at ASC"))
      end
    end
  end
end
