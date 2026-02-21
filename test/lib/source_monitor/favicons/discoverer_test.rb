# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Favicons
    class DiscovererTest < ActiveSupport::TestCase
      ICON_BODY = "\x00\x00\x01\x00".b # Minimal ICO header bytes
      PNG_BODY = "\x89PNG\r\n\x1a\n".b  # Minimal PNG header bytes

      setup do
        SourceMonitor.reset_configuration!
        @website_url = "https://example.com"
      end

      # -- nil / blank website_url --

      test "returns nil for nil website_url" do
        result = Discoverer.new(nil).call
        assert_nil result
      end

      test "returns nil for blank website_url" do
        result = Discoverer.new("").call
        assert_nil result
      end

      # -- try_favicon_ico --

      test "returns Result when /favicon.ico returns 200 with valid content type" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 200, body: ICON_BODY, headers: { "Content-Type" => "image/x-icon" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "image/x-icon", result.content_type
        assert_equal "favicon.ico", result.filename
        assert_equal "https://example.com/favicon.ico", result.url
        assert_equal ICON_BODY, result.io.read
      end

      test "returns nil when /favicon.ico returns 404" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404, body: "Not Found")

        # Also stub HTML page and Google API to return failures for full cascade
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><head></head></html>", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_return(status: 404, body: "")

        result = Discoverer.new(@website_url).call
        assert_nil result
      end

      # -- try_html_link_tags --

      test "discovers favicon from HTML link[rel=icon] tag" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = <<~HTML
          <html>
          <head>
            <link rel="icon" href="https://example.com/icon.png" sizes="32x32">
          </head>
          </html>
        HTML
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/icon.png")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "image/png", result.content_type
        assert_equal "icon.png", result.filename
      end

      test "prefers largest icon by sizes attribute" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = <<~HTML
          <html>
          <head>
            <link rel="icon" href="/small.png" sizes="16x16">
            <link rel="icon" href="/large.png" sizes="256x256">
            <link rel="icon" href="/medium.png" sizes="32x32">
          </head>
          </html>
        HTML
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/large.png")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "https://example.com/large.png", result.url
      end

      test "resolves relative URLs to absolute" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = <<~HTML
          <html>
          <head>
            <link rel="icon" href="/icons/favicon.png">
          </head>
          </html>
        HTML
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/icons/favicon.png")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "https://example.com/icons/favicon.png", result.url
        assert_equal "favicon.png", result.filename
      end

      # -- try_google_favicon_api --

      test "falls back to Google Favicon API" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><head></head></html>", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "image/png", result.content_type
        assert_equal "https://www.google.com/s2/favicons?domain=example.com&sz=64", result.url
      end

      # -- Cascade behavior --

      test "cascade: /favicon.ico 404 -> HTML has icon -> returns HTML result" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = '<html><head><link rel="shortcut icon" href="/my-icon.ico"></head></html>'
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/my-icon.ico")
          .to_return(status: 200, body: ICON_BODY, headers: { "Content-Type" => "image/x-icon" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "https://example.com/my-icon.ico", result.url
      end

      test "cascade: all fail -> returns nil" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><head></head></html>", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_return(status: 404)

        result = Discoverer.new(@website_url).call
        assert_nil result
      end

      # -- Validation --

      test "rejects non-image content types" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 200, body: "not an image", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><head></head></html>", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_return(status: 200, body: "not an image", headers: { "Content-Type" => "text/html" })

        result = Discoverer.new(@website_url).call
        assert_nil result
      end

      test "rejects oversized responses" do
        settings = SourceMonitor.config.favicons
        settings.max_download_size = 10 # 10 bytes

        oversized_body = "x" * 20
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 200, body: oversized_body, headers: { "Content-Type" => "image/x-icon" })
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><head></head></html>", headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_return(status: 200, body: oversized_body, headers: { "Content-Type" => "image/x-icon" })

        result = Discoverer.new(@website_url, settings: settings).call
        assert_nil result
      end

      # -- Error handling --

      test "returns nil on Faraday::Error for all strategies" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_raise(Faraday::ConnectionFailed.new("connection refused"))
        stub_request(:get, "https://example.com")
          .to_raise(Faraday::ConnectionFailed.new("connection refused"))
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_raise(Faraday::ConnectionFailed.new("connection refused"))

        result = Discoverer.new(@website_url).call
        assert_nil result
      end

      test "returns nil on Timeout::Error for all strategies" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_raise(Timeout::Error.new("execution expired"))
        stub_request(:get, "https://example.com")
          .to_raise(Timeout::Error.new("execution expired"))
        stub_request(:get, "https://www.google.com/s2/favicons?domain=example.com&sz=64")
          .to_raise(Timeout::Error.new("execution expired"))

        result = Discoverer.new(@website_url).call
        assert_nil result
      end

      # -- apple-touch-icon support --

      test "discovers apple-touch-icon" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = <<~HTML
          <html>
          <head>
            <link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
          </head>
          </html>
        HTML
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/apple-touch-icon.png")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "apple-touch-icon.png", result.filename
      end

      # -- msapplication-TileImage support --

      test "discovers msapplication-TileImage meta tag" do
        stub_request(:get, "https://example.com/favicon.ico")
          .to_return(status: 404)

        html = <<~HTML
          <html>
          <head>
            <meta name="msapplication-TileImage" content="/tile.png">
          </head>
          </html>
        HTML
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html, headers: { "Content-Type" => "text/html" })
        stub_request(:get, "https://example.com/tile.png")
          .to_return(status: 200, body: PNG_BODY, headers: { "Content-Type" => "image/png" })

        result = Discoverer.new(@website_url).call

        assert_not_nil result
        assert_equal "tile.png", result.filename
      end
    end
  end
end
