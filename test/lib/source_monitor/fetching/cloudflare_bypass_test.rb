# frozen_string_literal: true

require "test_helper"
require "faraday"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class CloudflareBypassTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      CF_CHALLENGE_HTML = '<html><head><title>Just a moment</title></head><body><div id="cf-challenge">Please wait</div></body></html>'
      VALID_RSS = nil # loaded in setup

      setup do
        SourceMonitor.reset_configuration!
        @feed_url = "https://example.com/cf-bypass-test.xml"
        @valid_rss = File.read(file_fixture("feeds/rss_sample.xml"))
        @cf_response = Struct.new(:status, :headers, :body, keyword_init: true).new(
          status: 200,
          headers: { "set-cookie" => "cf_clearance=abc123; Path=/" },
          body: CF_CHALLENGE_HTML
        )
      end

      test "returns nil when all strategies fail" do
        stub_request(:get, @feed_url).to_return(
          status: 200,
          body: CF_CHALLENGE_HTML,
          headers: { "Content-Type" => "text/html" }
        )

        bypass = CloudflareBypass.new(response: @cf_response, feed_url: @feed_url)
        result = bypass.call

        assert_nil result
      end

      test "cookie replay succeeds when server accepts cookies" do
        stub_request(:get, @feed_url)
          .with(headers: { "Cookie" => "cf_clearance=abc123" })
          .to_return(status: 200, body: @valid_rss, headers: { "Content-Type" => "application/rss+xml" })

        bypass = CloudflareBypass.new(response: @cf_response, feed_url: @feed_url)
        result = bypass.call

        assert_not_nil result
        assert_equal 200, result.status
        assert_includes result.body, "<rss"
      end

      test "UA rotation succeeds when one UA works" do
        # No cookies in this response
        no_cookie_response = Struct.new(:status, :headers, :body, keyword_init: true).new(
          status: 200,
          headers: {},
          body: CF_CHALLENGE_HTML
        )

        # First two UAs still blocked, third succeeds
        call_count = 0
        stub_request(:get, @feed_url).to_return { |_req|
          call_count += 1
          if call_count <= 2
            { status: 200, body: CF_CHALLENGE_HTML, headers: { "Content-Type" => "text/html" } }
          else
            { status: 200, body: @valid_rss, headers: { "Content-Type" => "application/rss+xml" } }
          end
        }

        bypass = CloudflareBypass.new(response: no_cookie_response, feed_url: @feed_url)
        result = bypass.call

        assert_not_nil result
        assert_includes result.body, "<rss"
      end

      test "cookie replay is tried before UA rotation" do
        # Cookie replay returns CF page, but first UA works
        call_count = 0
        stub_request(:get, @feed_url).to_return { |_req|
          call_count += 1
          if call_count == 1
            # Cookie replay attempt still blocked
            { status: 200, body: CF_CHALLENGE_HTML, headers: { "Content-Type" => "text/html" } }
          else
            # First UA rotation attempt succeeds
            { status: 200, body: @valid_rss, headers: { "Content-Type" => "application/rss+xml" } }
          end
        }

        bypass = CloudflareBypass.new(response: @cf_response, feed_url: @feed_url)
        result = bypass.call

        assert_not_nil result
        # 1 cookie replay + at least 1 UA rotation
        assert call_count >= 2
      end

      test "skips cookie replay when no Set-Cookie header present" do
        no_cookie_response = Struct.new(:status, :headers, :body, keyword_init: true).new(
          status: 200,
          headers: {},
          body: CF_CHALLENGE_HTML
        )

        # All requests return CF page
        stub_request(:get, @feed_url).to_return(
          status: 200,
          body: CF_CHALLENGE_HTML,
          headers: { "Content-Type" => "text/html" }
        )

        bypass = CloudflareBypass.new(response: no_cookie_response, feed_url: @feed_url)
        result = bypass.call

        assert_nil result
      end

      test "handles HTTP errors gracefully during bypass attempts" do
        stub_request(:get, @feed_url).to_raise(Faraday::ConnectionFailed.new("refused"))

        bypass = CloudflareBypass.new(response: @cf_response, feed_url: @feed_url)
        result = bypass.call

        assert_nil result
      end

      test "uses cache-busting headers on every request" do
        stub_request(:get, @feed_url)
          .with(headers: { "Cache-Control" => "no-cache", "Pragma" => "no-cache" })
          .to_return(status: 200, body: @valid_rss, headers: { "Content-Type" => "application/rss+xml" })

        bypass = CloudflareBypass.new(response: @cf_response, feed_url: @feed_url)
        result = bypass.call

        assert_not_nil result
      end

      test "USER_AGENTS contains at least 4 real browser strings" do
        assert CloudflareBypass::USER_AGENTS.length >= 4
        CloudflareBypass::USER_AGENTS.each do |ua|
          assert ua.include?("Mozilla/5.0"), "UA should look like a real browser: #{ua}"
        end
      end
    end
  end
end
