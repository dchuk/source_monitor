# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FaviconIntegrationTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      SourceMonitor.reset_configuration!
    end

    test "creating a source enqueues and performs favicon fetch end-to-end" do
      # Step 1: Create source via POST
      assert_difference -> { Source.count }, 1 do
        post "/source_monitor/sources", params: {
          source: {
            name: "Integration Favicon Source",
            feed_url: "https://integration-favicon.example.com/feed.xml",
            website_url: "https://integration-favicon.example.com",
            fetch_interval_minutes: 60
          }
        }
      end

      source = Source.order(:created_at).last
      assert_redirected_to "/source_monitor/sources/#{source.id}"

      # Step 2: Assert FaviconFetchJob was enqueued
      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob, args: [ source.id ])

      # Step 3: Perform the job with Discoverer stubbed
      fake_icon_data = "fake-png-icon-bytes"
      fake_result = SourceMonitor::Favicons::Discoverer::Result.new(
        io: StringIO.new(fake_icon_data),
        filename: "favicon.png",
        content_type: "image/png",
        url: "https://integration-favicon.example.com/favicon.png"
      )

      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        mock = Minitest::Mock.new
        mock.expect(:call, fake_result)
        mock
      }) do
        FaviconFetchJob.new.perform(source.id)
      end

      # Step 4: Assert favicon is attached
      source.reload
      assert source.favicon.attached?, "Expected favicon to be attached after job execution"
      assert_equal "favicon.png", source.favicon.filename.to_s
      assert_equal "image/png", source.favicon.content_type

      # Step 5: Verify source show page renders without error
      get "/source_monitor/sources/#{source.id}"
      assert_response :success
    end

    test "creating a source without website_url does not enqueue favicon job" do
      post "/source_monitor/sources", params: {
        source: {
          name: "No Website Integration Source",
          feed_url: "https://no-website-integration.example.com/feed.xml",
          website_url: "",
          fetch_interval_minutes: 60
        }
      }

      assert_response :redirect

      assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob)
    end

    test "creating a source with favicons disabled does not enqueue favicon job" do
      SourceMonitor.config.favicons.enabled = false

      post "/source_monitor/sources", params: {
        source: {
          name: "Disabled Integration Source",
          feed_url: "https://disabled-integration.example.com/feed.xml",
          website_url: "https://disabled-integration.example.com",
          fetch_interval_minutes: 60
        }
      }

      assert_response :redirect

      assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob)
    end
  end
end
