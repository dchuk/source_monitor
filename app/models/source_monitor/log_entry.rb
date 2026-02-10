# frozen_string_literal: true

module SourceMonitor
  class LogEntry < ApplicationRecord
    delegated_type :loggable, types: %w[SourceMonitor::FetchLog SourceMonitor::ScrapeLog SourceMonitor::HealthCheckLog]

    belongs_to :source, class_name: "SourceMonitor::Source", inverse_of: :log_entries
    belongs_to :item, class_name: "SourceMonitor::Item", inverse_of: :log_entries, optional: true

    validates :started_at, presence: true
    validates :source, presence: true

    scope :recent, -> { order(started_at: :desc) }

    SourceMonitor::ModelExtensions.register(self, :log_entry)

    class << self
      def ransackable_attributes(_auth_object = nil)
        %w[
          success
          started_at
          http_status
          scraper_adapter
          error_message
          error_class
          loggable_type
        ]
      end

      def ransackable_associations(_auth_object = nil)
        %w[source item loggable]
      end
    end

    def fetch?
      loggable_type == FetchLog.sti_name
    end

    def scrape?
      loggable_type == ScrapeLog.sti_name
    end

    def health_check?
      loggable_type == HealthCheckLog.sti_name
    end

    def log_type
      return :fetch if fetch?
      return :scrape if scrape?

      :health_check
    end
  end
end
