# frozen_string_literal: true

module SourceMonitor
  class ImportHistory < ApplicationRecord
    validates :user_id, presence: true

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
  end
end
