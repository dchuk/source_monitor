# frozen_string_literal: true

module SourceMonitor
  module Analytics
    class ScrapeRecommendations
      def initialize(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
        @threshold = threshold.to_i
      end

      def candidates_count
        @candidates_count ||= Source.scrape_candidates(threshold: @threshold).count
      end

      def candidate_ids
        @candidate_ids ||= Source.scrape_candidates(threshold: @threshold).pluck(:id)
      end

      def candidate?(source_id)
        candidate_ids.include?(source_id)
      end

      private

      attr_reader :threshold
    end
  end
end
