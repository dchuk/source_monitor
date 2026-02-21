# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcher
      class SourceUpdaterFaviconTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        setup do
          SourceMonitor.reset_configuration!
          @source = create_source!(
            website_url: "https://example.com",
            metadata: {},
            adaptive_fetching_enabled: false
          )
          @adaptive_interval = AdaptiveInterval.new(source: @source, jitter_proc: ->(_) { 0 })
          @updater = SourceUpdater.new(source: @source, adaptive_interval: @adaptive_interval)
        end

        test "update_source_for_success enqueues FaviconFetchJob when favicon not attached" do
          response = stub_response(200)

          assert_enqueued_with(job: SourceMonitor::FaviconFetchJob, args: [ @source.id ]) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success does not enqueue when favicon already attached" do
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new("existing-icon"),
            filename: "existing.ico",
            content_type: "image/x-icon"
          )
          @source.favicon.attach(blob)

          response = stub_response(200)

          assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success does not enqueue when within cooldown period" do
          @source.update_column(:metadata, {
            "favicon_last_attempted_at" => 1.day.ago.iso8601
          })

          response = stub_response(200)

          assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success enqueues when outside cooldown period" do
          @source.update_column(:metadata, {
            "favicon_last_attempted_at" => 10.days.ago.iso8601
          })

          response = stub_response(200)

          assert_enqueued_with(job: SourceMonitor::FaviconFetchJob, args: [ @source.id ]) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success does not enqueue when favicons disabled" do
          SourceMonitor.config.favicons.enabled = false

          response = stub_response(200)

          assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success does not enqueue when website_url blank" do
          @source.update_columns(website_url: nil)

          response = stub_response(200)

          assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
            @updater.update_source_for_success(response, 100, stub_feed, "sig123")
          end
        end

        test "update_source_for_success does not error when enqueue fails" do
          SourceMonitor::FaviconFetchJob.stub(:perform_later, ->(_id) { raise StandardError, "queue down" }) do
            response = stub_response(200)

            assert_nothing_raised do
              @updater.update_source_for_success(response, 100, stub_feed, "sig123")
            end
          end

          @source.reload
          assert_not_nil @source.last_fetched_at, "source should still be updated despite enqueue failure"
        end

        test "update_source_for_not_modified enqueues favicon when not attached" do
          response = stub_response(304)

          assert_enqueued_with(job: SourceMonitor::FaviconFetchJob, args: [ @source.id ]) do
            @updater.update_source_for_not_modified(response, 50)
          end
        end

        test "update_source_for_not_modified does not enqueue when favicon already attached" do
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new("existing-icon"),
            filename: "existing.ico",
            content_type: "image/x-icon"
          )
          @source.favicon.attach(blob)

          response = stub_response(304)

          assert_no_enqueued_jobs(only: SourceMonitor::FaviconFetchJob) do
            @updater.update_source_for_not_modified(response, 50)
          end
        end

        private

        def stub_response(status)
          Struct.new(:status, :headers).new(status, {})
        end

        def stub_feed
          klass = Class.new do
            def entries
              []
            end

            def self.name
              "Feedjira::Parser::RSS"
            end
          end
          klass.new
        end
      end
    end
  end
end
