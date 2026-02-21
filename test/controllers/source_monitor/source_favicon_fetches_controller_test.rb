# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceFaviconFetchesControllerTest < ActionDispatch::IntegrationTest
    include SourceMonitor::Engine.routes.url_helpers

    setup do
      SourceMonitor.reset_configuration!
      @source = create_source!(name: "Favicon Test Source", website_url: "https://example.com")
    end

    test "enqueues favicon fetch job and renders turbo stream" do
      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob, args: [ @source.id ]) do
        post source_favicon_fetch_path(@source), as: :turbo_stream
      end

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", @response.media_type
      assert_includes @response.body, "Favicon fetch has been enqueued"
    end

    test "purges existing favicon before enqueuing" do
      # Attach a favicon first
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("\x89PNG\r\n\x1a\n"),
        filename: "old-favicon.png",
        content_type: "image/png"
      )
      @source.favicon.attach(blob)
      assert @source.favicon.attached?

      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob) do
        post source_favicon_fetch_path(@source), as: :turbo_stream
      end

      @source.reload
      assert_not @source.favicon.attached?
    end

    test "warns when favicons disabled" do
      SourceMonitor.configure { |c| c.favicons.enabled = false }

      post source_favicon_fetch_path(@source), as: :turbo_stream

      assert_response :success
      assert_includes @response.body, "not enabled"
    end

    test "handles errors with turbo stream toast" do
      SourceMonitor::FaviconFetchJob.stub(:perform_later, ->(*) { raise StandardError, "boom" }) do
        post source_favicon_fetch_path(@source), as: :turbo_stream
      end

      assert_response :unprocessable_entity
      assert_includes @response.body, "Favicon fetch could not be enqueued"
    end

    test "clears favicon cooldown before enqueuing" do
      @source.update_column(:metadata, { "favicon_last_attempted_at" => 1.hour.ago.iso8601 })

      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob) do
        post source_favicon_fetch_path(@source), as: :turbo_stream
      end

      @source.reload
      assert_nil @source.metadata&.dig("favicon_last_attempted_at")
    end

    test "redirects on HTML request" do
      assert_enqueued_with(job: SourceMonitor::FaviconFetchJob) do
        post source_favicon_fetch_path(@source)
      end

      assert_redirected_to source_path(@source)
    end
  end
end
