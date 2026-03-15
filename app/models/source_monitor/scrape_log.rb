# frozen_string_literal: true

module SourceMonitor
  class ScrapeLog < ApplicationRecord
    include SourceMonitor::Loggable

    belongs_to :item, class_name: "SourceMonitor::Item", inverse_of: :scrape_logs
    belongs_to :source, class_name: "SourceMonitor::Source", inverse_of: :scrape_logs
    has_one :log_entry, as: :loggable, class_name: "SourceMonitor::LogEntry", inverse_of: :loggable, dependent: :destroy

    scope :by_source, ->(source) { where(source: source) }
    scope :by_status, ->(success) { where(success: success) }
    scope :by_item, ->(item) { where(item: item) }

    validates :item, :source, presence: true
    validates :content_length, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validate :source_matches_item

    SourceMonitor::ModelExtensions.register(self, :scrape_log)

    private

    def source_matches_item
      return if item.nil? || source.nil?

      errors.add(:source, "must match item source") if item.source_id != source_id
    end
  end
end
