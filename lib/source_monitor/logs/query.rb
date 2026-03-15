# frozen_string_literal: true

module SourceMonitor
  module Logs
    class Query
      Result = Struct.new(
        :entries,
        :page,
        :per_page,
        :has_next_page,
        :has_previous_page,
        :total_count,
        :filter_set,
        keyword_init: true
      ) do
        def has_next_page?
          !!self[:has_next_page]
        end

        def has_previous_page?
          !!self[:has_previous_page]
        end

        def next_page
          return nil unless has_next_page?

          page + 1
        end

        def previous_page
          return nil unless has_previous_page?

          [ page - 1, 1 ].max
        end

        def total_pages
          return 1 if total_count.nil? || total_count <= 0

          [ 1, (total_count.to_f / per_page).ceil ].max
        end
      end

      def initialize(params:)
        @filter_set = SourceMonitor::Logs::FilterSet.new(params:)
      end

      def call
        pagination_result = SourceMonitor::Pagination::Paginator.new(
          scope: filtered_scope,
          page: filter_set.page,
          per_page: filter_set.per_page
        ).paginate

        Result.new(
          entries: pagination_result.records,
          page: pagination_result.page,
          per_page: pagination_result.per_page,
          has_next_page: pagination_result.has_next_page?,
          has_previous_page: pagination_result.has_previous_page?,
          total_count: pagination_result.total_count,
          filter_set:
        )
      end

      private

      attr_reader :filter_set

      def filtered_scope
        scope = SourceMonitor::LogEntry.includes(:source, :item, :loggable).recent
        scope = scope.where(success: filter_set.success_flag) unless filter_set.success_flag.nil?
        scope = scope.where(loggable_type: filter_set.loggable_type) if filter_set.loggable_type
        scope = scope.where(source_id: filter_set.source_id) if filter_set.source_id
        scope = scope.where(item_id: filter_set.item_id) if filter_set.item_id
        scope = scope.where("sourcemon_log_entries.started_at >= ?", filter_set.effective_started_after) if filter_set.effective_started_after
        scope = scope.where("sourcemon_log_entries.started_at <= ?", filter_set.started_before) if filter_set.started_before
        scope = apply_search(scope, filter_set.search) if filter_set.search
        scope.order(started_at: :desc, id: :desc)
      end

      def apply_search(scope, term)
        normalized = "%#{term.to_s.downcase}%"

        scope.
          left_outer_joins(:source).
          left_outer_joins(:item).
          where(
            <<~SQL.squish,
              (LOWER(sourcemon_log_entries.error_message) LIKE :query) OR
              (LOWER(sourcemon_log_entries.error_class) LIKE :query) OR
              (CAST(sourcemon_log_entries.http_status AS TEXT) LIKE :query) OR
              (LOWER(sourcemon_log_entries.scraper_adapter) LIKE :query) OR
              (LOWER(sourcemon_sources.name) LIKE :query) OR
              (LOWER(sourcemon_items.title) LIKE :query)
            SQL
            query: normalized
          )
      end
    end
  end
end
