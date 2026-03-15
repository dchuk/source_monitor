# frozen_string_literal: true

module SourceMonitor
  class ImportHistory < ApplicationRecord
    attribute :imported_sources, default: -> { [] }
    attribute :failed_sources, default: -> { [] }
    attribute :skipped_duplicates, default: -> { [] }
    attribute :bulk_settings, default: -> { {} }

    validates :user_id, presence: true
    validate :completed_at_after_started_at

    scope :not_dismissed, -> { where(dismissed_at: nil) }

    scope :recent_for, lambda { |user_id|
      scope = order(created_at: :desc)
      scope = scope.where(user_id: user_id) if user_id
      scope
    }

    def imported_count
      Array(imported_sources).size
    end

    def failed_count
      Array(failed_sources).size
    end

    def skipped_count
      Array(skipped_duplicates).size
    end

    def completed?
      completed_at.present?
    end

    def duration_ms
      return unless started_at && completed_at

      ((completed_at - started_at) * 1000).round
    end

    private

    def completed_at_after_started_at
      return if completed_at.blank? || started_at.blank?

      errors.add(:completed_at, "must be after started_at") if completed_at < started_at
    end
  end
end
