# frozen_string_literal: true

module SourceMonitor
  module Analytics
    class SourcesIndexMetrics
      FETCH_INTERVAL_KEYS = %w[
        fetch_interval_minutes_gteq
        fetch_interval_minutes_lt
        fetch_interval_minutes_lteq
      ].freeze

      attr_reader :search_params

      def initialize(base_scope:, result_scope:, search_params:, lookback: SourceActivityRates::DEFAULT_LOOKBACK, now: Time.current)
        @base_scope = base_scope
        @result_scope = result_scope
        @search_params = (search_params || {}).dup
        @lookback = lookback
        @now = now
      end

      def fetch_interval_distribution
        @fetch_interval_distribution ||= SourceFetchIntervalDistribution.new(scope: distribution_scope).buckets
      end

      def selected_fetch_interval_bucket
        filter = fetch_interval_filter
        return if filter.blank?

        fetch_interval_distribution.find do |bucket|
          min_match = filter[:min].present? ? filter[:min].to_i == bucket.min.to_i : bucket.min.nil?
          max_match = if bucket.max.nil?
            filter[:max].nil?
          else
            filter[:max].present? && filter[:max].to_i == bucket.max.to_i
          end

          min_match && max_match
        end
      end

      def item_activity_rates
        @item_activity_rates ||= SourceActivityRates.new(scope: result_scope, lookback:, now:).per_source_rates
      end

      def word_count_averages(source_ids)
        if source_ids.any?
          base = SourceMonitor::ItemContent.joins(:item).where(sourcemon_items: { source_id: source_ids })
          feed = base.where.not(feed_word_count: nil)
                     .group("sourcemon_items.source_id")
                     .average(:feed_word_count)
          scraped = base.where.not(scraped_word_count: nil)
                       .group("sourcemon_items.source_id")
                       .average(:scraped_word_count)
          { feed:, scraped: }
        else
          { feed: {}, scraped: {} }
        end
      end

      def fetch_interval_filter
        min = integer_param(search_params["fetch_interval_minutes_gteq"])
        max = integer_param(search_params["fetch_interval_minutes_lt"]) || integer_param(search_params["fetch_interval_minutes_lteq"])
        return if min.nil? && max.nil?

        { min:, max: }
      end

      private

      attr_reader :base_scope, :result_scope, :lookback, :now

      def distribution_scope
        @distribution_scope ||= begin
          filtered_params = search_params.except(*FETCH_INTERVAL_KEYS)

          if filtered_params.present? && base_scope.respond_to?(:ransack)
            base_scope.ransack(filtered_params).result
          else
            base_scope
          end
        end
      end

      def integer_param(value)
        return if value.blank?

        sanitized = SourceMonitor::Security::ParameterSanitizer.sanitize(value.to_s)
        cleaned = sanitized.strip
        return if cleaned.blank?

        Integer(cleaned)
      rescue ArgumentError, TypeError
        nil
      end

      def distribution_source_ids
        scope = distribution_scope
        if scope.respond_to?(:pluck)
          scope.pluck(:id)
        else
          Array(scope).map { |record| record.respond_to?(:id) ? record.id : record }
        end
      end
    end
  end
end
