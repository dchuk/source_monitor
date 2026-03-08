# frozen_string_literal: true

module SourceMonitor
  class BulkScrapeEnablementsController < ApplicationController
    def create
      source_ids = Array(params.dig(:bulk_scrape_enablement, :source_ids)).map(&:to_i).reject(&:zero?)

      if source_ids.empty?
        handle_empty_selection
        return
      end

      sources = Source.where(id: source_ids, scraping_enabled: false)
      updated_count = sources.update_all(
        scraping_enabled: true,
        scraper_adapter: default_adapter,
        updated_at: Time.current
      )

      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(
            message: "Scraping enabled for #{updated_count} #{'source'.pluralize(updated_count)}.",
            level: :success
          )
          responder.redirect(source_monitor.sources_path)
          render turbo_stream: responder.render(view_context)
        end
        format.html do
          redirect_to source_monitor.sources_path,
            notice: "Scraping enabled for #{updated_count} #{'source'.pluralize(updated_count)}."
        end
      end
    end

    private

    def default_adapter
      "readability"
    end

    def handle_empty_selection
      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(message: "No sources selected.", level: :warning)
          render turbo_stream: responder.render(view_context), status: :unprocessable_entity
        end
        format.html do
          redirect_to source_monitor.sources_path, alert: "No sources selected."
        end
      end
    end
  end
end
