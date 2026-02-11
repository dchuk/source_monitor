# frozen_string_literal: true

module SourceMonitor
  parent_job = defined?(::ApplicationJob) ? ::ApplicationJob : ActiveJob::Base

  class ApplicationJob < parent_job
    class << self
      # Specify a queue name using SourceMonitor's configuration, ensuring
      # we respect host application prefixes and overrides.
      def source_monitor_queue(role)
        queue_as SourceMonitor.queue_name(role)
      end
    end
  end
end
