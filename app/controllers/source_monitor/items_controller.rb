# frozen_string_literal: true

module SourceMonitor
  class ItemsController < ApplicationController
    include ActionView::RecordIdentifier
    include SourceMonitor::SanitizesSearchParams

    searchable_with scope: -> { Item.active.includes(:source) }, default_sorts: [ "published_at desc", "created_at desc" ]

    PER_PAGE = 25
    SEARCH_FIELD = :title_or_summary_or_url_or_source_name_cont

    before_action :set_item, only: %i[show scrape]
    before_action :load_scrape_context, only: :show

    def index
      @search_params = sanitized_search_params
      @q = build_search_query

      scope = @q.result(distinct: true)
      paginator = SourceMonitor::Pagination::Paginator.new(
        scope:,
        page: params[:page],
        per_page: PER_PAGE
      ).paginate

      @items = paginator.records
      @page = paginator.page
      @has_next_page = paginator.has_next_page
      @has_previous_page = paginator.has_previous_page

      @search_term = @search_params[SEARCH_FIELD.to_s].to_s.strip
      @search_field = SEARCH_FIELD
    end

    def show
    end

    # TODO: Extract to ItemScrapesController (CRUD-only convention).
    # Deferred to avoid view/route churn in a cleanup phase.
    def scrape
      log_manual_scrape("controller:start", item: @item, extra: { format: request.format })

      enqueue_result = SourceMonitor::Scraping::Enqueuer.enqueue(item: @item, reason: :manual)
      log_manual_scrape(
        "controller:enqueue_result",
        item: @item,
        extra: { status: enqueue_result.status, message: enqueue_result.message }
      )
      flash_key, flash_message = scrape_flash_payload(enqueue_result)
      status = enqueue_result.failure? ? :unprocessable_entity : :ok

      respond_to do |format|
        format.turbo_stream do
          log_manual_scrape("controller:respond_turbo", item: @item, extra: { status: status })

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
          log_manual_scrape("controller:respond_html", item: @item)
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
      @item = Item.active.includes(:source, :item_content).find(params[:id])
    end

    def load_scrape_context
      @recent_scrape_logs = @item.scrape_logs.order(started_at: :desc).limit(5)
      @latest_scrape_log = @recent_scrape_logs.first
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

    def log_manual_scrape(stage, item:, extra: {})
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      payload = { stage:, item_id: item&.id }.merge(extra.compact)
      Rails.logger.info("[SourceMonitor::ManualScrape] #{payload.to_json}")
    rescue StandardError
      nil
    end
  end
end
