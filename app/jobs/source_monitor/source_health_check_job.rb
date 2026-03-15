# frozen_string_literal: true

module SourceMonitor
  class SourceHealthCheckJob < ApplicationJob
    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    def perform(source_id)
      source = SourceMonitor::Source.find_by(id: source_id)
      return unless source

      SourceMonitor::Health::SourceHealthCheckOrchestrator.new(source).call
    end
  end
end
