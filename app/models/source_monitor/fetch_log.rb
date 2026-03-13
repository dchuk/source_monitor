# frozen_string_literal: true

module SourceMonitor
  class FetchLog < ApplicationRecord
    include SourceMonitor::Loggable

    belongs_to :source, class_name: "SourceMonitor::Source", inverse_of: :fetch_logs
    has_one :log_entry, as: :loggable, class_name: "SourceMonitor::LogEntry", inverse_of: :loggable, dependent: :destroy

    attribute :items_created, :integer, default: 0
    attribute :items_updated, :integer, default: 0
    attribute :items_failed, :integer, default: 0
    attribute :http_response_headers, default: -> { {} }

    ERROR_CATEGORIES = %w[network parse blocked auth unknown].freeze

    validates :source, presence: true
    validates :items_created, :items_updated, :items_failed,
              numericality: { greater_than_or_equal_to: 0 }
    validates :error_category, inclusion: { in: ERROR_CATEGORIES }, allow_nil: true

    scope :for_job, ->(job_id) { where(job_id:) }
    scope :by_category, ->(category) { where(error_category: category) }

    SourceMonitor::ModelExtensions.register(self, :fetch_log)

    after_save :sync_log_entry

    private

    def sync_log_entry
      SourceMonitor::Logs::EntrySync.call(self)
    end
  end
end
