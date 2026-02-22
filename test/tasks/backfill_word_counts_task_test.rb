# frozen_string_literal: true

require "test_helper"
require "rake"

module SourceMonitor
  class BackfillWordCountsTaskTest < ActiveSupport::TestCase
    setup do
      clean_source_monitor_tables!
      Rails.application.load_tasks unless Rake::Task.task_defined?("source_monitor:backfill_word_counts")
    end

    test "backfill_word_counts populates word counts for existing records" do
      source = create_source!
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/backfill-#{SecureRandom.hex(4)}",
        title: "Backfill Test",
        content: "<p>Hello world from feed</p>"
      )
      content = SourceMonitor::ItemContent.create!(item: item, scraped_content: "Hello world from scraper")

      # Manually nil out word counts to simulate pre-migration state
      content.update_columns(scraped_word_count: nil, feed_word_count: nil)
      content.reload
      assert_nil content.scraped_word_count
      assert_nil content.feed_word_count

      # Run the rake task
      Rake::Task["source_monitor:backfill_word_counts"].reenable
      assert_output(/Done\. Backfilled word counts for \d+ records\./) do
        Rake::Task["source_monitor:backfill_word_counts"].invoke
      end

      content.reload
      assert_equal 4, content.scraped_word_count
      assert_equal 4, content.feed_word_count
    end
  end
end
