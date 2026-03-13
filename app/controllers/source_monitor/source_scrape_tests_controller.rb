# frozen_string_literal: true

module SourceMonitor
  class SourceScrapeTestsController < ApplicationController
    before_action :set_source

    def create
      item = pick_test_item
      unless item
        handle_no_item
        return
      end

      result = SourceMonitor::Scraping::ItemScraper.new(item: item, source: @source).call

      @test_result = {
        item: item.reload,
        scrape_result: result,
        feed_word_count: item.item_content&.feed_word_count,
        scraped_word_count: item.item_content&.scraped_word_count,
        feed_content_preview: item.content.to_s.truncate(500),
        scraped_content_preview: item.item_content&.scraped_content.to_s.truncate(500),
        improvement: compute_improvement(item)
      }

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("scrape_test_modal_#{@source.id}"),
            turbo_stream.append_all("body",
              partial: "source_monitor/source_scrape_tests/result",
              locals: { source: @source, test_result: @test_result })
          ]
        end
        format.html { render :show }
      end
    end

    private

    def set_source
      @source = Source.find(params[:source_id])
    end

    def pick_test_item
      @source.items
             .joins(:item_content)
             .where.not(sourcemon_item_contents: { feed_word_count: nil })
             .order(published_at: :desc)
             .first
    end

    def handle_no_item
      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(message: "No items with feed content available for test scrape.", level: :warning)
          render turbo_stream: responder.render(view_context)
        end
        format.html do
          redirect_to source_monitor.source_path(@source), alert: "No items available for test scrape."
        end
      end
    end

    def compute_improvement(item)
      feed = item.item_content&.feed_word_count.to_i
      scraped = item.item_content&.scraped_word_count.to_i
      return 0 if feed.zero?
      ((scraped - feed).to_f / feed * 100).round(1)
    end
  end
end
