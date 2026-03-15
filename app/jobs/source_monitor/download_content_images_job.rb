# frozen_string_literal: true

module SourceMonitor
  class DownloadContentImagesJob < ApplicationJob
    source_monitor_queue :maintenance

    discard_on ActiveJob::DeserializationError

    def perform(item_id)
      item = SourceMonitor::Item.find_by(id: item_id)
      return unless item

      SourceMonitor::Images::Processor.new(item).call
    end
  end
end
