# frozen_string_literal: true

module SourceMonitor
  class SourceHealthChecksController < ApplicationController
    include SourceMonitor::SourceTurboResponses
    include SourceMonitor::SetSource

    PROCESSING_BADGE = {
      label: "Processing",
      classes: "bg-blue-100 text-blue-700",
      show_spinner: true,
      status: "processing"
    }.freeze

    before_action :set_source

    def create
      SourceMonitor::SourceHealthCheckJob.perform_later(@source.id)
      render_fetch_enqueue_response(
        "Health check enqueued",
        health_status_override: PROCESSING_BADGE
      )
    rescue StandardError => error
      handle_fetch_failure(error, prefix: "Health check")
    end
  end
end
