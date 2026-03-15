# frozen_string_literal: true

module SourceMonitor
  class ItemsController < ApplicationController
    include ActionView::RecordIdentifier
    include SourceMonitor::SanitizesSearchParams

    searchable_with scope: -> { Item.active.includes(:source, :item_content) }, default_sorts: [ "published_at desc", "created_at desc" ]

    PER_PAGE = 25
    SEARCH_FIELD = :title_or_summary_or_url_or_source_name_cont

    before_action :set_item, only: :show
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

      @paginator = paginator
      @items = paginator.records
      @page = paginator.page
      @has_next_page = paginator.has_next_page
      @has_previous_page = paginator.has_previous_page

      @search_term = @search_params[SEARCH_FIELD.to_s].to_s.strip
      @search_field = SEARCH_FIELD
    end

    def show
    end

    private

    def set_item
      @item = Item.active.includes(:source, :item_content).find(params[:id])
    end

    def load_scrape_context
      @recent_scrape_logs = @item.scrape_logs.order(started_at: :desc).limit(5)
      @latest_scrape_log = @recent_scrape_logs.first
    end
  end
end
