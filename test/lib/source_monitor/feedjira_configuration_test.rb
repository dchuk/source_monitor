# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FeedjiraConfigurationTest < ActiveSupport::TestCase
    test "sets parser order and trims whitespace" do
      assert_equal Feedjira::Parser::JSONFeed, Feedjira.parsers.first
      assert Feedjira.strip_whitespace
    end

    test "parses sample rss and json feeds" do
      rss_feed = File.read(file_fixture("feeds/rss_sample.xml"))
      rss = Feedjira.parse(rss_feed)

      assert_equal "Example RSS Feed", rss.title
      assert_equal 1, rss.entries.size
      assert_equal "First item content.", rss.entries.first.summary

      json_feed = File.read(file_fixture("feeds/json_feed_sample.json"))
      json = Feedjira.parse(json_feed)

      assert_equal "Example JSON Feed", json.title
      assert_equal [ "json-1" ], json.entries.map(&:id)
    end
  end
end
