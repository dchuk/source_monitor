# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module Completion
      # Enqueues follow-up scraping work for items created during a fetch.
      class FollowUpHandler
        Result = Struct.new(:status, :enqueued_count, :errors, keyword_init: true) do
          def success?
            status != :failed
          end
        end

        def initialize(enqueuer_class: SourceMonitor::Scraping::Enqueuer, job_class: SourceMonitor::ScrapeItemJob)
          @enqueuer_class = enqueuer_class
          @job_class = job_class
        end

        def call(source:, result:)
          return Result.new(status: :skipped, enqueued_count: 0, errors: []) unless should_enqueue?(source:, result:)

          enqueued = 0
          errors = []

          Array(result.item_processing&.created_items).each do |item|
            next unless item.present? && item.scraped_at.nil?

            begin
              enqueuer_class.enqueue(item:, source:, job_class:, reason: :auto)
              enqueued += 1
            rescue StandardError => error
              errors << error
              Rails.logger.error(
                "[SourceMonitor::Fetching::Completion::FollowUpHandler] Failed to enqueue scrape for item #{item.id}: #{error.class}: #{error.message}"
              ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
            end
          end

          Result.new(status: :applied, enqueued_count: enqueued, errors: errors)
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
