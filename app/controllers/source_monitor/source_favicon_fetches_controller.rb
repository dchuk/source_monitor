# frozen_string_literal: true

module SourceMonitor
  class SourceFaviconFetchesController < ApplicationController
    include SourceMonitor::SourceTurboResponses
    include SourceMonitor::SetSource

    before_action :set_source

    def create
      unless defined?(ActiveStorage) && SourceMonitor.config.favicons.enabled?
        return render_fetch_enqueue_response("Favicon fetching is not enabled.", toast_level: :warning)
      end

      if @source.respond_to?(:favicon) && @source.favicon.attached?
        @source.favicon.purge
      end

      # Clear cooldown so the job doesn't skip this attempt
      @source.clear_favicon_cooldown!

      SourceMonitor::FaviconFetchJob.perform_later(@source.id)
      render_fetch_enqueue_response("Favicon fetch has been enqueued.")
    rescue StandardError => error
      handle_fetch_failure(error, prefix: "Favicon fetch")
    end
  end
end
