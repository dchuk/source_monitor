# frozen_string_literal: true

module SourceMonitor
  class SourceRetriesController < ApplicationController
    include SourceMonitor::SourceTurboResponses
    include SourceMonitor::SetSource

    before_action :set_source

    def create
      result = SourceMonitor::Fetching::FetchRunner.enqueue(@source.id, force: true)

      if result == :already_fetching
        render_fetch_enqueue_response(
          "Fetch already in progress for this source. Please wait for the current fetch to complete.",
          toast_level: :warning
        )
      else
        render_fetch_enqueue_response("Retry has been forced and will run shortly.")
      end
    rescue StandardError => error
      handle_fetch_failure(error)
    end
  end
end
