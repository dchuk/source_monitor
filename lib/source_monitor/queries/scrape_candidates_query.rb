# frozen_string_literal: true

module SourceMonitor
  module Queries
    class ScrapeCandidatesQuery
      def initialize(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
        @threshold = threshold.to_i
      end

      def call
        return SourceMonitor::Source.none if @threshold <= 0

        SourceMonitor::Source.active
          .where(scraping_enabled: false)
          .where(id: source_ids_below_threshold)
      end

      private

      def source_ids_below_threshold
        SourceMonitor::Item
          .joins(:item_content)
          .where.not(SourceMonitor::ItemContent.table_name => { feed_word_count: nil })
          .group(:source_id)
          .having("AVG(#{SourceMonitor::ItemContent.table_name}.feed_word_count) < ?", @threshold)
          .select(:source_id)
      end
    end
  end
end
