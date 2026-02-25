# frozen_string_literal: true

module SourceMonitor
  class ScheduleFetchesJob < ApplicationJob
    source_monitor_queue :fetch

    def perform(options = nil)
      limit = extract_limit(options)
      SourceMonitor::Scheduler.run(limit:)
    end

    private

    def extract_limit(options)
      options_hash =
        case options
        when nil then {}
        when Hash then options
        else {}
        end

      if options_hash.respond_to?(:symbolize_keys)
        options_hash = options_hash.symbolize_keys
      end

      options_hash[:limit] || SourceMonitor.config.fetching.scheduler_batch_size
    end
  end
end
