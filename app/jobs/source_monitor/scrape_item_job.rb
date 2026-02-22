# frozen_string_literal: true

module SourceMonitor
  class ScrapeItemJob < ApplicationJob
    source_monitor_queue :scrape

    discard_on ActiveJob::DeserializationError

    def perform(item_id)
      log("job:start", item_id: item_id)
      item = SourceMonitor::Item.includes(:source).find_by(id: item_id)
      return unless item

      source = item.source
      unless source&.scraping_enabled?
        log("job:skipped_scraping_disabled", item: item)
        SourceMonitor::Scraping::State.clear_inflight!(item)
        return
      end

      remaining = time_until_scrape_allowed(source)
      if remaining&.positive?
        SourceMonitor::Scraping::State.clear_inflight!(item)
        self.class.set(wait: remaining.seconds).perform_later(item_id)
        log("job:deferred", item: item, wait_seconds: remaining)
        return
      end

      SourceMonitor::Scraping::State.mark_processing!(item)
      SourceMonitor::Scraping::ItemScraper.new(item:, source:).call
      log("job:completed", item: item, status: item.scrape_status)
    rescue StandardError => error
      log("job:error", item: item, error: error.message)
      SourceMonitor::Scraping::State.mark_failed!(item)
      raise
    ensure
      SourceMonitor::Scraping::State.clear_inflight!(item) if item
    end

    private

    def time_until_scrape_allowed(source)
      interval = source.min_scrape_interval || SourceMonitor.config.scraping.min_scrape_interval
      return nil if interval.nil? || interval <= 0

      last_scrape_at = source.scrape_logs.maximum(:started_at)
      return nil unless last_scrape_at

      elapsed = Time.current - last_scrape_at
      remaining = interval - elapsed
      remaining.positive? ? remaining.ceil : nil
    end

    def log(stage, item: nil, item_id: nil, **extra)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      payload = {
        stage: "SourceMonitor::ScrapeItemJob##{stage}",
        item_id: item&.id || item_id,
        source_id: item&.source_id
      }.merge(extra.compact)
      Rails.logger.info("[SourceMonitor::ManualScrape] #{payload.to_json}")
    rescue StandardError
      nil
    end
  end
end
