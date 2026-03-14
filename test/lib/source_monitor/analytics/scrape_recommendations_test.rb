# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Analytics
    class ScrapeRecommendationsTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.configure do |config|
          config.scraping.scrape_recommendation_threshold = 200
        end

        @low_wc_source = create_source!(name: "Low WC #{SecureRandom.hex(4)}", scraping_enabled: false)
        item1 = SourceMonitor::Item.create!(
          source: @low_wc_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/sr-#{SecureRandom.hex(4)}",
          content: "short feed content"
        )
        item1.reload # ensure callback-created ItemContent is loaded

        @high_wc_source = create_source!(name: "High WC #{SecureRandom.hex(4)}", scraping_enabled: false)
        words = Array.new(300) { "word" }.join(" ")
        item2 = SourceMonitor::Item.create!(
          source: @high_wc_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/sr-#{SecureRandom.hex(4)}",
          content: words
        )
        item2.reload # ensure callback-created ItemContent is loaded

        @scraping_enabled_source = create_source!(name: "Scraping On #{SecureRandom.hex(4)}", scraping_enabled: true)
        item3 = SourceMonitor::Item.create!(
          source: @scraping_enabled_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/sr-#{SecureRandom.hex(4)}",
          content: "short content"
        )
        item3.reload # ensure callback-created ItemContent is loaded
      end

      test "candidates_count returns correct count" do
        recs = ScrapeRecommendations.new(threshold: 200)
        assert_operator recs.candidates_count, :>=, 1
        # low_wc_source should be a candidate, high_wc_source should not
      end

      test "candidate_ids returns correct IDs" do
        recs = ScrapeRecommendations.new(threshold: 200)
        ids = recs.candidate_ids
        assert_includes ids, @low_wc_source.id
        assert_not_includes ids, @high_wc_source.id
        assert_not_includes ids, @scraping_enabled_source.id
      end

      test "candidate? returns true for candidate source" do
        recs = ScrapeRecommendations.new(threshold: 200)
        assert recs.candidate?(@low_wc_source.id)
      end

      test "candidate? returns false for non-candidate source" do
        recs = ScrapeRecommendations.new(threshold: 200)
        assert_not recs.candidate?(@high_wc_source.id)
        assert_not recs.candidate?(@scraping_enabled_source.id)
      end

      test "results are memoized" do
        recs = ScrapeRecommendations.new(threshold: 200)
        ids_first = recs.candidate_ids
        ids_second = recs.candidate_ids
        assert_same ids_first, ids_second

        count_first = recs.candidates_count
        count_second = recs.candidates_count
        assert_equal count_first, count_second
      end

      test "respects threshold parameter" do
        # With threshold of 5, even the low_wc_source (3 words) is a candidate
        recs = ScrapeRecommendations.new(threshold: 5)
        assert_includes recs.candidate_ids, @low_wc_source.id

        # With threshold of 1, nothing qualifies
        recs_low = ScrapeRecommendations.new(threshold: 1)
        assert_not_includes recs_low.candidate_ids, @low_wc_source.id
      end
    end
  end
end
