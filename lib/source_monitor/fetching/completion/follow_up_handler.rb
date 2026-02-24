# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module Completion
      # Enqueues follow-up scraping work for items created during a fetch.
      class FollowUpHandler
        def initialize(enqueuer_class: SourceMonitor::Scraping::Enqueuer, job_class: SourceMonitor::ScrapeItemJob)
          @enqueuer_class = enqueuer_class
          @job_class = job_class
        end

        def call(source:, result:)
          return unless should_enqueue?(source:, result:)

          Array(result.item_processing&.created_items).each do |item|
            next unless item.present? && item.scraped_at.nil?

            begin
              enqueuer_class.enqueue(item:, source:, job_class:, reason: :auto)
            rescue StandardError => error
              Rails.logger.error(
                "[SourceMonitor] FollowUpHandler: failed to enqueue scrape for item #{item.id}: #{error.class}: #{error.message}"
              ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
            end
          end
        end

        private

        attr_reader :enqueuer_class, :job_class

        def should_enqueue?(source:, result:)
          return false unless result
          return false unless result.status == :fetched
          return false unless source.scraping_enabled? && source.auto_scrape?

          result.item_processing&.created.to_i.positive?
        end
      end
    end
  end
end
