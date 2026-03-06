# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class SourceUpdaterErrorCategoryTest < ActiveSupport::TestCase
      setup do
        @source = create_source!(name: "Category Test", feed_url: "https://example.com/category.xml")
        adaptive = FeedFetcher::AdaptiveInterval.new(source: @source, jitter_proc: ->(_) { 0 })
        @updater = FeedFetcher::SourceUpdater.new(source: @source, adaptive_interval: adaptive)
      end

      test "categorizes TimeoutError as network" do
        error = TimeoutError.new("timed out")
        log = create_error_log(error)
        assert_equal "network", log.error_category
      end

      test "categorizes ConnectionError as network" do
        error = ConnectionError.new("refused")
        log = create_error_log(error)
        assert_equal "network", log.error_category
      end

      test "categorizes HTTPError 500 as network" do
        error = HTTPError.new(status: 500)
        log = create_error_log(error)
        assert_equal "network", log.error_category
      end

      test "categorizes HTTPError 401 as auth" do
        error = HTTPError.new(status: 401)
        log = create_error_log(error)
        assert_equal "auth", log.error_category
      end

      test "categorizes HTTPError 403 as auth" do
        error = HTTPError.new(status: 403)
        log = create_error_log(error)
        assert_equal "auth", log.error_category
      end

      test "categorizes HTTPError 404 as network" do
        error = HTTPError.new(status: 404)
        log = create_error_log(error)
        assert_equal "network", log.error_category
      end

      test "categorizes ParsingError as parse" do
        error = ParsingError.new("bad feed")
        log = create_error_log(error)
        assert_equal "parse", log.error_category
      end

      test "categorizes BlockedError as blocked" do
        error = BlockedError.new(blocked_by: "cloudflare")
        log = create_error_log(error)
        assert_equal "blocked", log.error_category
      end

      test "categorizes AuthenticationError as auth" do
        error = AuthenticationError.new
        log = create_error_log(error)
        assert_equal "auth", log.error_category
      end

      test "categorizes UnexpectedResponseError as unknown" do
        error = UnexpectedResponseError.new("weird")
        log = create_error_log(error)
        assert_equal "unknown", log.error_category
      end

      test "categorizes base FetchError as unknown" do
        error = FetchError.new("generic")
        log = create_error_log(error)
        assert_equal "unknown", log.error_category
      end

      test "returns nil error_category for successful fetch log" do
        log = @updater.create_fetch_log(
          response: stub_response(200),
          duration_ms: 100,
          started_at: Time.current,
          success: true
        )
        assert_nil log.error_category
      end

      private

      def create_error_log(error)
        @updater.create_fetch_log(
          response: stub_response(error.http_status || 0),
          duration_ms: 100,
          started_at: Time.current,
          success: false,
          error: error
        )
      end

      def stub_response(status)
        FeedFetcher::ResponseWrapper.new(status: status, headers: {}, body: "")
      end
    end
  end
end
