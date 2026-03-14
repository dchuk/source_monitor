# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Queries
    class ScrapeCandidatesQueryTest < ActiveSupport::TestCase
      setup do
        @source = Source.create!(name: "Query Test", feed_url: "https://example.com/query-test", scraping_enabled: false)
      end

      test "returns sources with avg feed word count below threshold" do
        item = Item.create!(source: @source, guid: SecureRandom.uuid, url: "https://example.com/q-#{SecureRandom.hex(4)}", content: "short content here")
        ItemContent.create!(item: item)

        results = ScrapeCandidatesQuery.new(threshold: 500).call

        assert_includes results, @source
      end

      test "excludes sources above threshold" do
        words = Array.new(600) { "word" }.join(" ")
        item = Item.create!(source: @source, guid: SecureRandom.uuid, url: "https://example.com/q-#{SecureRandom.hex(4)}", content: words)
        ItemContent.create!(item: item)

        results = ScrapeCandidatesQuery.new(threshold: 500).call

        assert_not_includes results, @source
      end

      test "excludes sources with scraping enabled" do
        @source.update!(scraping_enabled: true)
        item = Item.create!(source: @source, guid: SecureRandom.uuid, url: "https://example.com/q-#{SecureRandom.hex(4)}", content: "short content here")
        ItemContent.create!(item: item)

        results = ScrapeCandidatesQuery.new(threshold: 500).call

        assert_not_includes results, @source
      end

      test "excludes inactive sources" do
        @source.update!(active: false)
        item = Item.create!(source: @source, guid: SecureRandom.uuid, url: "https://example.com/q-#{SecureRandom.hex(4)}", content: "short content here")
        ItemContent.create!(item: item)

        results = ScrapeCandidatesQuery.new(threshold: 500).call

        assert_not_includes results, @source
      end

      test "returns none for zero or negative threshold" do
        item = Item.create!(source: @source, guid: SecureRandom.uuid, url: "https://example.com/q-#{SecureRandom.hex(4)}", content: "short content here")
        ItemContent.create!(item: item)

        assert_empty ScrapeCandidatesQuery.new(threshold: 0).call
        assert_empty ScrapeCandidatesQuery.new(threshold: -1).call
      end
    end
  end
end
