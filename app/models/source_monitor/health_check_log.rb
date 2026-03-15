# frozen_string_literal: true

module SourceMonitor
  class HealthCheckLog < ApplicationRecord
    include SourceMonitor::Loggable

    belongs_to :source, class_name: "SourceMonitor::Source", inverse_of: :health_check_logs
    has_one :log_entry,
            as: :loggable,
            class_name: "SourceMonitor::LogEntry",
            inverse_of: :loggable,
            dependent: :destroy

    attribute :http_response_headers, default: -> { {} }

    validates :source, presence: true

    SourceMonitor::ModelExtensions.register(self, :health_check_log)
  end
end
