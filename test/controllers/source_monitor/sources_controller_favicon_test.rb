# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourcesControllerFaviconTest < ActionDispatch::IntegrationTest
    setup do
      SourceMonitor.reset_configuration!
    end

    test "create with website_url enqueues FaviconFetchJob" do
      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob) do
        post "/source_monitor/sources", params: {
          source: {
            name: "Favicon Source",
            feed_url: "https://favicon-test.example.com/feed.xml",
            website_url: "https://favicon-test.example.com",
            fetch_interval_minutes: 60
          }
        }
      end

      assert_response :redirect
    end

    test "create without website_url does not enqueue FaviconFetchJob" do
      assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
        post "/source_monitor/sources", params: {
          source: {
            name: "No Website Source",
            feed_url: "https://no-website.example.com/feed.xml",
            website_url: "",
            fetch_interval_minutes: 60
          }
        }
      end

      assert_response :redirect
    end

    test "create with favicons disabled does not enqueue FaviconFetchJob" do
      SourceMonitor.config.favicons.enabled = false

      assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
        post "/source_monitor/sources", params: {
          source: {
            name: "Disabled Favicon Source",
            feed_url: "https://disabled-favicon.example.com/feed.xml",
            website_url: "https://disabled-favicon.example.com",
            fetch_interval_minutes: 60
          }
        }
      end

      assert_response :redirect
    end

    test "create failure does not enqueue FaviconFetchJob" do
      assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
        post "/source_monitor/sources", params: {
          source: {
            name: "",
            feed_url: "",
            website_url: "https://invalid.example.com",
            fetch_interval_minutes: 60
          }
        }
      end
    end
  end
end
