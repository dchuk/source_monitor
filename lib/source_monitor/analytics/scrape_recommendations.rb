# frozen_string_literal: true

module SourceMonitor
  module Analytics
    class ScrapeRecommendations
      def initialize(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
        @threshold = threshold.to_i
      end

      def relation
        @relation ||= SourceMonitor::Queries::ScrapeCandidatesQuery.new(threshold: threshold).call
      end

      def candidates_count
        @candidates_count ||= relation.count
      end

      def candidate_ids
        @candidate_ids ||= relation.pluck(:id)
      end

      def candidate_ids_for(source_ids)
        ids = Array(source_ids).map { |source_id| source_id.respond_to?(:id) ? source_id.id : source_id }.compact
        return [] if ids.empty?

        relation.where(id: ids).pluck(:id)
      end

      def candidate?(source_id)
        candidate_ids.include?(source_id)
      end

      def filter_params
        {
          "scraping_enabled_eq" => "false",
          "active_eq" => "true",
          "avg_feed_words_lt" => threshold.to_s
        }
      end

      private

      attr_reader :threshold
    end
  end
end
