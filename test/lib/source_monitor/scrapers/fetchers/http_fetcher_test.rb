# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Scrapers
    module Fetchers
      class HttpFetcherTest < ActiveSupport::TestCase
        setup do
          @url = "https://example.com/articles/1"
          @fetcher = HttpFetcher.new
        end

        test "returns success result for 200 responses" do
          stub_request(:get, @url)
            .to_return(status: 200, body: "<html>ok</html>", headers: { "Content-Type" => "text/html" })

          result = @fetcher.fetch(url: @url, settings: { headers: {} })

          assert_equal :success, result.status
          assert_equal 200, result.http_status
          assert_includes result.body, "ok"
        end

        test "returns failure result for non-success status" do
          stub_request(:get, @url).to_return(status: 500, body: "error")

          result = @fetcher.fetch(url: @url, settings: {})

          assert_equal :failed, result.status
          assert_equal "Faraday::ServerError", result.error
          assert_includes result.message, "status 500"
        end

        test "captures faraday errors" do
          stub_request(:get, @url).to_raise(Faraday::ConnectionFailed.new("timeout"))

          result = @fetcher.fetch(url: @url, settings: {})

          assert_equal :failed, result.status
          assert_equal "Faraday::ConnectionFailed", result.error
          assert_equal "timeout", result.message
        end

        # -- AIA Certificate Resolution --

        test "retries with AIA resolution when SSLError occurs and intermediate found" do
          body = "<html><body>Article content</body></html>"
          call_count = 0
          stub_request(:get, @url).to_return do |_req|
            call_count += 1
            if call_count == 1
              raise Faraday::SSLError, "certificate verify failed"
            else
              { status: 200, body: body, headers: { "Content-Type" => "text/html" } }
            end
          end

          SourceMonitor::HTTP::AIAResolver.stub(:resolve, :mock_cert) do
            SourceMonitor::HTTP::AIAResolver.stub(:enhanced_cert_store, OpenSSL::X509::Store.new) do
              result = @fetcher.fetch(url: @url, settings: {})

              assert_equal :success, result.status
              assert_equal 200, result.http_status
              assert_includes result.body, "Article content"
            end
          end
        end

        test "returns failure when SSLError occurs and AIA resolve returns nil" do
          stub_request(:get, @url).to_raise(Faraday::SSLError.new("certificate verify failed"))

          SourceMonitor::HTTP::AIAResolver.stub(:resolve, nil) do
            result = @fetcher.fetch(url: @url, settings: {})

            assert_equal :failed, result.status
            assert_equal "Faraday::SSLError", result.error
            assert_includes result.message, "certificate verify failed"
          end
        end

        test "does not attempt AIA resolution for non-SSL ConnectionFailed" do
          stub_request(:get, @url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

          resolve_called = false
          resolve_stub = ->(_hostname) { resolve_called = true; nil }

          SourceMonitor::HTTP::AIAResolver.stub(:resolve, resolve_stub) do
            result = @fetcher.fetch(url: @url, settings: {})

            assert_equal :failed, result.status
            assert_equal "Faraday::ConnectionFailed", result.error
            refute resolve_called, "AIA resolve should not be called for non-SSL errors"
          end
        end
      end
    end
  end
end
