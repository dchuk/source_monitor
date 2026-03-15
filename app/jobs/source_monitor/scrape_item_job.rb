# frozen_string_literal: true

module SourceMonitor
  class ScrapeItemJob < ApplicationJob
    source_monitor_queue :scrape

    discard_on ActiveJob::DeserializationError

    rescue_from ActiveRecord::Deadlocked do |error|
      Rails.logger&.warn("[SourceMonitor::ScrapeItemJob] Deadlock: #{error.message}")
      retry_job(wait: 2.seconds + rand(3).seconds)
    end

    def perform(item_id)
      item = SourceMonitor::Item.includes(:source).find_by(id: item_id)
      return unless item

      SourceMonitor::Scraping::Runner.new(item).call
    end
  end
end
