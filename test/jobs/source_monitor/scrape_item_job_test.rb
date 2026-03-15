# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ScrapeItemJobTest < ActiveJob::TestCase
    test "delegates to Scraping::Runner" do
      source = create_source!(scraping_enabled: true, auto_scrape: true)
      item = create_item!(source: source)

      runner_called = false
      fake_runner = Object.new
      fake_runner.define_singleton_method(:call) { runner_called = true }

      SourceMonitor::Scraping::Runner.stub(:new, ->(_item) { fake_runner }) do
        SourceMonitor::ScrapeItemJob.perform_now(item.id)
      end

      assert runner_called, "expected Scraping::Runner#call to be invoked"
    end

    test "silently skips missing item" do
      assert_nothing_raised do
        SourceMonitor::ScrapeItemJob.perform_now(-1)
      end
    end

    test "end-to-end performs scraping via Runner" do
      source = create_source!(scraping_enabled: true, auto_scrape: true)
      item = create_item!(source: source)

      result = SourceMonitor::Scrapers::Base::Result.new(
        status: :success,
        html: "<article><p>Scraped HTML</p></article>",
        content: "Scraped body",
        metadata: { http_status: 200, extraction_strategy: "readability" }
      )

      SourceMonitor::Scrapers::Readability.stub(:call, result) do
        assert_difference("SourceMonitor::ScrapeLog.count", 1) do
          SourceMonitor::ScrapeItemJob.perform_now(item.id)
        end
      end

      item.reload
      assert_equal "success", item.scrape_status
      assert_equal "Scraped body", item.scraped_content
    end

    test "retries on ActiveRecord::Deadlocked" do
      source = create_source!(scraping_enabled: true, auto_scrape: true)
      item = create_item!(source: source)

      fake_runner = Object.new
      fake_runner.define_singleton_method(:call) { raise ActiveRecord::Deadlocked, "deadlock detected" }

      SourceMonitor::Scraping::Runner.stub(:new, ->(_item) { fake_runner }) do
        assert_enqueued_with(job: SourceMonitor::ScrapeItemJob) do
          SourceMonitor::ScrapeItemJob.perform_now(item.id)
        end
      end
    end

    test "enqueues on scrape queue" do
      assert_equal SourceMonitor.queue_name(:scrape), ScrapeItemJob.new.queue_name
    end
  end
end
