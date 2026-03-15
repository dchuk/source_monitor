# frozen_string_literal: true

module SourceMonitor
  class SourceHealthResetsController < ApplicationController
    include SourceMonitor::SourceTurboResponses
    include SourceMonitor::SetSource

    before_action :set_source

    def create
      SourceMonitor::Health::SourceHealthReset.call(source: @source)
      SourceMonitor::Realtime.broadcast_source(@source)

      render_fetch_enqueue_response(
        "Health state reset",
        toast_level: :success
      )
    rescue StandardError => error
      handle_fetch_failure(error, prefix: "Health reset")
    end
  end
end
