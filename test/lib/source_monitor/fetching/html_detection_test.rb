# frozen_string_literal: true

require "test_helper"
require "faraday"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class HtmlDetectionTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      setup do
        @source = build_source(name: "Detection Test", feed_url: "https://example.com/detect.xml")
        @fetcher = FeedFetcher.new(source: @source, jitter: ->(_) { 0 })
      end

      test "detects Cloudflare challenge page by title" do
        body = "<html><head><title>Just a moment</title></head><body>Checking your browser</body></html>"
        assert_equal "cloudflare", detect(body)
      end

      test "detects Cloudflare Attention Required page" do
        body = "<html><head><title>Attention Required</title></head><body></body></html>"
        assert_equal "cloudflare", detect(body)
      end

      test "detects Cloudflare by cf-challenge marker" do
        body = '<html><head><title>Test</title></head><body><div id="cf-challenge">challenge</div></body></html>'
        assert_equal "cloudflare", detect(body)
      end

      test "detects Cloudflare by cf-browser-verification marker" do
        body = '<html><body><div class="cf-browser-verification">verify</div></body></html>'
        assert_equal "cloudflare", detect(body)
      end

      test "detects Cloudflare by __cf_chl_ marker" do
        body = '<html><body><script src="/cdn-cgi/challenge-platform/h/b/scripts/__cf_chl_jschl_tk__"></script></body></html>'
        assert_equal "cloudflare", detect(body)
      end

      test "detects Cloudflare by data-ray attribute" do
        body = '<html><body><span data-ray="abc123">ray</span></body></html>'
        assert_equal "cloudflare", detect(body)
      end

      test "detects login wall by title Log in" do
        body = "<html><head><title>Log in</title></head><body></body></html>"
        assert_equal "login_wall", detect(body)
      end

      test "detects login wall by title Sign in (case insensitive)" do
        body = "<html><head><title>SIGN IN</title></head><body></body></html>"
        assert_equal "login_wall", detect(body)
      end

      test "detects login wall by HTML form with password field" do
        body = '<html><body><form action="/login"><input type="password" name="pass"></form></body></html>'
        assert_equal "login_wall", detect(body)
      end

      test "detects CAPTCHA by g-recaptcha" do
        body = '<html><body><div class="g-recaptcha" data-sitekey="abc"></div></body></html>'
        assert_equal "captcha", detect(body)
      end

      test "detects CAPTCHA by h-captcha" do
        body = '<html><body><div class="h-captcha" data-sitekey="abc"></div></body></html>'
        assert_equal "captcha", detect(body)
      end

      test "returns nil for valid RSS XML" do
        body = File.read(file_fixture("feeds/rss_sample.xml"))
        assert_nil detect(body)
      end

      test "returns nil for plain HTML without block markers" do
        body = "<html><head><title>My Blog</title></head><body><p>Hello world</p></body></html>"
        assert_nil detect(body)
      end

      test "returns nil for blank body" do
        assert_nil detect("")
        assert_nil detect(nil)
      end

      test "only inspects first 4KB of body" do
        # Place CF marker well past the 4KB limit
        padding = "x" * 5000
        body = "<html><body>#{padding}<title>Just a moment</title></body></html>"
        assert_nil detect(body)
      end

      test "detects marker within first 4KB" do
        body = "<html><head><title>Just a moment</title></head>" + ("x" * 5000)
        assert_equal "cloudflare", detect(body)
      end

      private

      def detect(body)
        @fetcher.send(:detect_blocked_response, body, nil)
      end
    end
  end
end
