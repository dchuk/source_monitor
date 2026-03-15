# frozen_string_literal: true

module SourceMonitor
  module Loggable
    extend ActiveSupport::Concern

    included do
      attribute :metadata, default: -> { {} }

      validates :started_at, presence: true
      validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

      scope :recent, -> { order(started_at: :desc) }
      scope :successful, -> { where(success: true) }
      scope :failed, -> { where(success: false) }
      scope :since, ->(date) { where(arel_table[:started_at].gteq(date)) }
      scope :before, ->(date) { where(arel_table[:started_at].lteq(date)) }
      scope :today, -> { since(Time.current.beginning_of_day) }
      scope :by_date_range, ->(start_date, end_date) { since(start_date).before(end_date) }

      after_save :sync_log_entry
    end

    private

    def sync_log_entry
      SourceMonitor::Logs::EntrySync.call(self)
    end
  end
end
