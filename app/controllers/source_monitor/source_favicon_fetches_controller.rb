# frozen_string_literal: true

module SourceMonitor
  class SourceFaviconFetchesController < ApplicationController
    include SourceMonitor::SourceTurboResponses

    before_action :set_source

    def create
      unless defined?(ActiveStorage) && SourceMonitor.config.favicons.enabled?
        return render_fetch_enqueue_response("Favicon fetching is not enabled.", toast_level: :warning)
      end

      if @source.respond_to?(:favicon) && @source.favicon.attached?
        @source.favicon.purge
      end

      # Clear cooldown so the job doesn't skip this attempt
      clear_favicon_cooldown(@source)

      SourceMonitor::FaviconFetchJob.perform_later(@source.id)
      render_fetch_enqueue_response("Favicon fetch has been enqueued.")
    rescue StandardError => error
      handle_fetch_failure(error, prefix: "Favicon fetch")
    end

    private

    def set_source
      @source = Source.find(params[:source_id])
    end

    def clear_favicon_cooldown(source)
      metadata = (source.metadata || {}).except("favicon_last_attempted_at")
      source.update_column(:metadata, metadata)
    end
  end
end
