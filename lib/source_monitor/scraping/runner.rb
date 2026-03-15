# frozen_string_literal: true

module SourceMonitor
  module Scraping
    # Orchestrates a single item scrape: pre-flight checks (scraping enabled?),
    # state management (mark_processing!, mark_failed!, clear_inflight!),
    # and delegation to ItemScraper. Extracted from ScrapeItemJob so scraping
    # logic can be invoked synchronously.
    class Runner
      def initialize(item)
        @item = item
        @source = item.source
      end

      def call
        unless source&.scraping_enabled?
          log("runner:skipped_scraping_disabled")
          State.clear_inflight!(item)
          return
        end

        State.mark_processing!(item)
        SourceMonitor::Scraping::ItemScraper.new(item: item, source: source).call
        log("runner:completed", status: item.scrape_status)
      rescue StandardError => error
        log("runner:error", error: error.message)
        State.mark_failed!(item)
        raise
      ensure
        State.clear_inflight!(item) if item
      end

      private

      attr_reader :item, :source

      def log(stage, **extra)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        payload = {
          stage: "SourceMonitor::Scraping::Runner##{stage}",
          item_id: item&.id,
          source_id: source&.id
        }.merge(extra.compact)
        level = stage.to_s.include?("error") ? :error : :info
        Rails.logger.public_send(level, "[SourceMonitor::Scraping::Runner] #{payload.to_json}")
      rescue StandardError
        nil
      end
    end
  end
end
