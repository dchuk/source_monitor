# frozen_string_literal: true

module SourceMonitor
  class ItemScrapesController < ApplicationController
    include ActionView::RecordIdentifier

    before_action :set_item

    def create
      log_manual_scrape("controller:start", extra: { format: request.format })

      enqueue_result = SourceMonitor::Scraping::Enqueuer.enqueue(item: @item, reason: :manual)
      log_manual_scrape("controller:enqueue_result", extra: { status: enqueue_result.status, message: enqueue_result.message })
      flash_key, flash_message = scrape_flash_payload(enqueue_result)
      status = enqueue_result.failure? ? :unprocessable_entity : :ok

      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new

          if enqueue_result.enqueued? || enqueue_result.already_enqueued?
            @item.reload
            responder.replace_details(
              @item,
              partial: "source_monitor/items/details_wrapper",
              locals: { item: @item }
            )
          end

          if flash_message
            level = flash_key == :notice ? :info : :error
            responder.toast(message: flash_message, level:, delay_ms: toast_delay_for(level))
          end

          render turbo_stream: responder.render(view_context), status: status
        end

        format.html do
          if flash_key && flash_message
            redirect_to source_monitor.item_path(@item), flash: { flash_key => flash_message }
          else
            redirect_to source_monitor.item_path(@item)
          end
        end
      end
    end

    private

    def set_item
      @item = Item.active.includes(:source, :item_content).find(params[:item_id])
    end

    def scrape_flash_payload(result)
      case result.status
      when :enqueued
        [ :notice, "Scrape has been enqueued and will run shortly." ]
      when :already_enqueued
        [ :notice, result.message ]
      else
        [ :alert, result.message || "Unable to enqueue scrape for this item." ]
      end
    end

    def log_manual_scrape(stage, extra: {})
      payload = { stage:, item_id: @item&.id }.merge(extra.compact)
      Rails.logger.info("[SourceMonitor::ManualScrape] #{payload.to_json}")
    end
  end
end
