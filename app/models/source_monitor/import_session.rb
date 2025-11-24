# frozen_string_literal: true

module SourceMonitor
  class ImportSession < ApplicationRecord
    STEP_ORDER = %w[upload preview health_check configure confirm].freeze

    validates :current_step, inclusion: { in: STEP_ORDER }
    validates :user_id, presence: true

    class << self
      def default_step
        STEP_ORDER.first
      end
    end

    def next_step
      index = STEP_ORDER.index(current_step)
      STEP_ORDER[index + 1] if index && index < STEP_ORDER.length - 1
    end

    def previous_step
      index = STEP_ORDER.index(current_step)
      STEP_ORDER[index - 1] if index&.positive?
    end
  end
end
