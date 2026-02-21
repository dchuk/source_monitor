# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FaviconFetchJobTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
      @source = create_source!(
        website_url: "https://example.com",
        metadata: {}
      )
    end

    test "attaches favicon when Discoverer returns result" do
      fake_result = SourceMonitor::Favicons::Discoverer::Result.new(
        io: StringIO.new("fake-icon-data"),
        filename: "favicon.ico",
        content_type: "image/x-icon",
        url: "https://example.com/favicon.ico"
      )

      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        mock = Minitest::Mock.new
        mock.expect(:call, fake_result)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      @source.reload
      assert @source.favicon.attached?
    end

    test "returns early with missing source_id" do
      assert_nothing_raised do
        FaviconFetchJob.new.perform(-999)
      end
    end

    test "returns early with blank website_url" do
      @source.update_columns(website_url: nil)

      discoverer_called = false
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        discoverer_called = true
        mock = Minitest::Mock.new
        mock.expect(:call, nil)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      assert_not discoverer_called
    end

    test "returns early when favicon already attached" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("existing-icon"),
        filename: "existing.ico",
        content_type: "image/x-icon"
      )
      @source.favicon.attach(blob)

      discoverer_called = false
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        discoverer_called = true
        mock = Minitest::Mock.new
        mock.expect(:call, nil)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      assert_not discoverer_called
    end

    test "returns early within cooldown period" do
      @source.update_column(:metadata, {
        "favicon_last_attempted_at" => 1.day.ago.iso8601
      })

      discoverer_called = false
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        discoverer_called = true
        mock = Minitest::Mock.new
        mock.expect(:call, nil)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      assert_not discoverer_called
    end

    test "proceeds when outside cooldown period" do
      @source.update_column(:metadata, {
        "favicon_last_attempted_at" => 10.days.ago.iso8601
      })

      fake_result = SourceMonitor::Favicons::Discoverer::Result.new(
        io: StringIO.new("icon-data"),
        filename: "favicon.ico",
        content_type: "image/x-icon",
        url: "https://example.com/favicon.ico"
      )

      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        mock = Minitest::Mock.new
        mock.expect(:call, fake_result)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      @source.reload
      assert @source.favicon.attached?
    end

    test "records failed attempt when Discoverer returns nil" do
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        mock = Minitest::Mock.new
        mock.expect(:call, nil)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      @source.reload
      assert_not_nil @source.metadata["favicon_last_attempted_at"]
    end

    test "records failed attempt and logs on Discoverer error" do
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        obj = Object.new
        def obj.call
          raise StandardError, "discovery exploded"
        end
        obj
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      @source.reload
      assert_not_nil @source.metadata["favicon_last_attempted_at"]
    end

    test "returns early when favicons disabled in config" do
      SourceMonitor.config.favicons.enabled = false

      discoverer_called = false
      SourceMonitor::Favicons::Discoverer.stub(:new, ->(_url, **_opts) {
        discoverer_called = true
        mock = Minitest::Mock.new
        mock.expect(:call, nil)
        mock
      }) do
        FaviconFetchJob.new.perform(@source.id)
      end

      assert_not discoverer_called
    end

    test "uses source_monitor_queue :fetch" do
      assert_equal SourceMonitor.config.queue_name_for(:fetch), FaviconFetchJob.new.queue_name
    end
  end
end
