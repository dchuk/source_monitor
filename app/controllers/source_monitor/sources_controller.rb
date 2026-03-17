# frozen_string_literal: true

require "source_monitor/sources/turbo_stream_presenter"
require "source_monitor/scraping/bulk_result_presenter"
require "source_monitor/sources/params"

module SourceMonitor
  class SourcesController < ApplicationController
    include ActionView::RecordIdentifier
    include SourceMonitor::SanitizesSearchParams

    searchable_with scope: -> { Source.all }, default_sorts: [ "created_at desc" ]

    ITEMS_PREVIEW_LIMIT = SourceMonitor::Scraping::BulkSourceScraper::DEFAULT_PREVIEW_LIMIT
    PER_PAGE = 25

    before_action :set_source, only: %i[show edit update destroy]

    SEARCH_FIELD = :name_or_feed_url_or_website_url_cont

    def index
      @search_params = sanitized_search_params
      expand_scrape_recommendation_filter
      @q = build_search_query(params: @search_params)

      @paginator = SourceMonitor::Pagination::Paginator.new(
        scope: @q.result,
        page: params[:page],
        per_page: params[:per_page] || PER_PAGE
      ).paginate

      @sources = @paginator.records

      @search_term = @search_params[SEARCH_FIELD.to_s].to_s.strip
      @search_field = SEARCH_FIELD

      metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
        base_scope: Source.all,
        result_scope: @paginator.records,
        search_params: @search_params
      )

      @recent_import_histories = SourceMonitor::ImportHistory.not_dismissed.recent_for(source_monitor_current_user&.id).limit(5)

      @fetch_interval_distribution = metrics.fetch_interval_distribution
      @fetch_interval_filter = metrics.fetch_interval_filter
      @selected_fetch_interval_bucket = metrics.selected_fetch_interval_bucket
      @item_activity_rates = metrics.item_activity_rates

      source_ids = @sources.map(&:id)
      word_counts = metrics.word_count_averages(source_ids)
      @avg_feed_word_counts = word_counts[:feed]
      @avg_scraped_word_counts = word_counts[:scraped]

      @scrape_candidate_ids = compute_scrape_candidate_ids
      @total_scrape_candidate_count = Source.scrape_candidates.count

      # Row partial preload requirements (V3): item_activity_rates,
      # avg_feed_word_counts, avg_scraped_word_counts are pre-computed above
      # and passed as locals to avoid N+1 queries in _row.html.erb.
      adapter_options = Source.distinct.where.not(scraper_adapter: [ nil, "" ]).order(:scraper_adapter).pluck(:scraper_adapter)
      @filter_presenter = SourceMonitor::SourcesFilterPresenter.new(
        search_params: @search_params,
        search_term: @search_term,
        fetch_interval_filter: @fetch_interval_filter,
        adapter_options: adapter_options
      )
    end

    def show
      @recent_fetch_logs = @source.fetch_logs.order(started_at: :desc).limit(5)
      @recent_scrape_logs = @source.scrape_logs.order(started_at: :desc).limit(5)
      @items = @source.items.recent.includes(:item_content).limit(ITEMS_PREVIEW_LIMIT)
      @bulk_scrape_selection = :current
    end

    def new
      @source = Source.new(default_attributes)
    end

    def create
      @source = Source.new(source_params)

      if @source.save
        enqueue_favicon_fetch(@source)
        redirect_to source_monitor.source_path(@source), notice: "Source created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      scraping_was_disabled = !@source.scraping_enabled?

      if @source.update(source_params)
        notice = "Source updated successfully"

        if scraping_was_disabled && @source.scraping_enabled?
          enqueued = enqueue_unscraped_items(@source)
          notice = "Auto-scraping enabled. #{enqueued} existing #{'item'.pluralize(enqueued)} queued for scraping."
        end

        redirect_to source_monitor.source_path(@source), notice: notice
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      search_params = sanitized_search_params

      begin
        unless @source.destroy
          handle_destroy_failure(search_params, "Could not delete source: #{@source.errors.full_messages.join(', ')}")
          return
        end
      rescue ActiveRecord::InvalidForeignKey
        handle_destroy_failure(search_params, "Cannot delete source: other records still reference it. Remove dependent records first.")
        return
      end

      message = "Source deleted"

      respond_to do |format|
        format.turbo_stream do
          query = build_search_query(params: search_params)

          metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
            base_scope: Source.all,
            result_scope: query.result,
            search_params:
          )

          redirect_location = SourceMonitor::Security::ParameterSanitizer.safe_redirect_path(params[:redirect_to])

          responder = SourceMonitor::TurboStreams::StreamResponder.new
          presenter = SourceMonitor::Sources::TurboStreamPresenter.new(source: @source, responder:)

          presenter.render_deletion(
            metrics:,
            query:,
            search_params:,
            redirect_location:
          )

          responder.toast(message:, level: :success)

          render turbo_stream: responder.render(view_context)
        end

        format.html do
          redirect_to source_monitor.sources_path, notice: message
        end
      end
    end

    private

    def set_source
      @source = Source.find(params[:id])
    end

    def default_attributes
      SourceMonitor::Sources::Params.default_attributes
    end

    def source_params
      SourceMonitor::Sources::Params.sanitize(params)
    end

    def handle_destroy_failure(search_params, error_message)
      respond_to do |format|
        format.turbo_stream do
          responder = SourceMonitor::TurboStreams::StreamResponder.new
          responder.toast(message: error_message, level: :error)
          render turbo_stream: responder.render(view_context), status: :unprocessable_entity
        end

        format.html do
          redirect_to source_monitor.sources_path(q: search_params), alert: error_message
        end
      end
    end

    def expand_scrape_recommendation_filter
      return unless @search_params["scraping_enabled_eq"] == "recommend"

      threshold = SourceMonitor.config.scraping.scrape_recommendation_threshold
      @search_params.delete("scraping_enabled_eq")
      @search_params["scraping_enabled_eq"] = "false"
      @search_params["active_eq"] = "true"
      @search_params["avg_feed_words_lt"] = threshold.to_s
    end

    def compute_scrape_candidate_ids
      threshold = SourceMonitor.config.scraping.scrape_recommendation_threshold
      return Set.new if threshold.nil? || threshold <= 0

      candidate_ids = @sources.select do |source|
        avg = @avg_feed_word_counts[source.id]
        avg.present? && avg < threshold && !source.scraping_enabled?
      end.map(&:id)

      Set.new(candidate_ids)
    end

    def enqueue_unscraped_items(source)
      result = SourceMonitor::Scraping::BulkSourceScraper.new(
        source: source,
        selection: :unscraped
      ).call
      result.enqueued_count
    rescue StandardError => error
      Rails.logger.warn("[SourceMonitor] Failed to enqueue unscraped items: #{error.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      0
    end

    def enqueue_favicon_fetch(source)
      return unless defined?(ActiveStorage)
      return unless SourceMonitor.config.favicons.enabled?
      return if source.website_url.blank?

      SourceMonitor::FaviconFetchJob.perform_later(source.id)
    rescue StandardError => error
      Rails.logger.warn("[SourceMonitor] Failed to enqueue favicon fetch: #{error.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    end
  end
end
