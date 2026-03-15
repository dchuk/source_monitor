# frozen_string_literal: true

module SourceMonitor
  class SourceBulkScrapesController < ApplicationController
    include SourceMonitor::SourceTurboResponses
    include SourceMonitor::SetSource

    ITEMS_PREVIEW_LIMIT = SourceMonitor::Scraping::BulkSourceScraper::DEFAULT_PREVIEW_LIMIT

    before_action :set_source

    def create
      selection = bulk_scrape_params[:selection]
      normalized_selection = SourceMonitor::Scraping::BulkSourceScraper.normalize_selection(selection) || :current
      @bulk_scrape_selection = normalized_selection

      result = SourceMonitor::Scraping::BulkSourceScraper.new(
        source: @source,
        selection: normalized_selection,
        preview_limit: ITEMS_PREVIEW_LIMIT
      ).call

      respond_to_bulk_scrape(result)
    end

    private

    def bulk_scrape_params
      params.fetch(:bulk_scrape, {}).permit(:selection)
    end
  end
end
