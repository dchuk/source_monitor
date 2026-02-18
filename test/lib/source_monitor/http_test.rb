# frozen_string_literal: true

require "test_helper"
require "openssl"
require "stringio"
require "zlib"

module SourceMonitor
  class HTTPTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
      @connection = SourceMonitor::HTTP.client
    end

    teardown do
      SourceMonitor.reset_configuration!
    end

    test "configures faraday connection with timeouts, redirects, and compression" do
      handlers = @connection.builder.handlers

      assert_equal SourceMonitor::HTTP::DEFAULT_TIMEOUT, @connection.options.timeout
      assert_equal SourceMonitor::HTTP::DEFAULT_OPEN_TIMEOUT, @connection.options.open_timeout

      follow_redirects = handlers.find { |handler| handler.klass == Faraday::FollowRedirects::Middleware }

      refute_nil follow_redirects
      assert_equal SourceMonitor::HTTP::DEFAULT_MAX_REDIRECTS,
                   follow_redirects.instance_variable_get(:@kwargs)[:limit]
      assert_includes handlers.map(&:klass), Faraday::FollowRedirects::Middleware
      assert_includes handlers.map(&:klass), Faraday::Gzip::Middleware
      assert_includes handlers.map(&:klass), Faraday::Response::RaiseError
    end

    test "adds retry middleware with exponential backoff" do
      retry_handler = @connection.builder.handlers.find { |handler| handler.klass == Faraday::Retry::Middleware }
      refute_nil retry_handler

      options = retry_handler.instance_variable_get(:@kwargs)

      assert_equal 4, options[:max]
      assert_equal 0.5, options[:interval]
      assert_equal 0.5, options[:interval_randomness]
      assert_equal 2, options[:backoff_factor]
      assert_equal SourceMonitor::HTTP::RETRY_STATUSES, options[:retry_statuses]
    end

    test "can disable retry middleware" do
      connection = SourceMonitor::HTTP.client(retry_requests: false)

      refute_includes connection.builder.handlers.map(&:klass), Faraday::Retry::Middleware
    end

    test "uses configured http settings" do
      SourceMonitor.configure do |config|
        config.http.timeout = 45
        config.http.open_timeout = 15
        config.http.max_redirects = 7
        config.http.retry_max = 6
        config.http.retry_interval = 1.0
        config.http.retry_interval_randomness = 0.25
        config.http.retry_backoff_factor = 3
        config.http.retry_statuses = [ 418, 429 ]
      end

      connection = SourceMonitor::HTTP.client
      handlers = connection.builder.handlers

      assert_equal 45, connection.options.timeout
      assert_equal 15, connection.options.open_timeout

      follow_redirects = handlers.find { |handler| handler.klass == Faraday::FollowRedirects::Middleware }
      refute_nil follow_redirects
      assert_equal 7, follow_redirects.instance_variable_get(:@kwargs)[:limit]

      retry_handler = handlers.find { |handler| handler.klass == Faraday::Retry::Middleware }
      options = retry_handler.instance_variable_get(:@kwargs)

      assert_equal 6, options[:max]
      assert_in_delta 1.0, options[:interval]
      assert_in_delta 0.25, options[:interval_randomness]
      assert_equal 3, options[:backoff_factor]
      assert_equal [ 418, 429 ], options[:retry_statuses]
    end

    test "supports proxy arguments" do
      proxy_connection = SourceMonitor::HTTP.client(proxy: "http://proxy.test:8080")

      assert_equal "http://proxy.test:8080", proxy_connection.proxy.uri.to_s
    end

    test "allows overriding headers while preserving defaults" do
      custom = SourceMonitor::HTTP.client(headers: { "User-Agent" => "SourceMonitor/Test" })

      assert_equal "SourceMonitor/Test", custom.headers["User-Agent"]
      assert_equal "application/rss+xml, application/atom+xml, application/json;q=0.9, text/xml;q=0.8", custom.headers["Accept"]
      assert_equal "gzip,deflate", custom.headers["Accept-Encoding"]
    end

    test "merges configured headers and user agent" do
      SourceMonitor.configure do |config|
        config.http.user_agent = -> { "SourceMonitor/Custom" }
        config.http.headers = {
          "Accept" => "application/json",
          "X-Feed-Monitor" => "true"
        }
      end

      client = SourceMonitor::HTTP.client(headers: { "X-Request-ID" => "abc123" })

      assert_equal "SourceMonitor/Custom", client.headers["User-Agent"]
      assert_equal "application/json", client.headers["Accept"]
      assert_equal "true", client.headers["X-Feed-Monitor"]
      assert_equal "abc123", client.headers["X-Request-ID"]
    end

    test "configures SSL with default cert store" do
      assert @connection.ssl.verify
      assert_instance_of OpenSSL::X509::Store, @connection.ssl.cert_store
      assert_nil @connection.ssl.ca_file
    end

    test "uses configured ssl_ca_file when set" do
      SourceMonitor.configure do |config|
        config.http.ssl_ca_file = "/path/to/custom/ca.pem"
      end

      connection = SourceMonitor::HTTP.client
      assert_equal "/path/to/custom/ca.pem", connection.ssl.ca_file
      assert_nil connection.ssl.cert_store
    end

    test "uses configured ssl_ca_path when set" do
      SourceMonitor.configure do |config|
        config.http.ssl_ca_path = "/path/to/certs"
      end

      connection = SourceMonitor::HTTP.client
      assert_equal "/path/to/certs", connection.ssl.ca_path
    end

    test "ssl verify defaults to true" do
      assert_equal true, @connection.ssl.verify
    end

    test "respects ssl_verify configuration" do
      SourceMonitor.configure do |config|
        config.http.ssl_verify = false
      end

      connection = SourceMonitor::HTTP.client
      assert_equal false, connection.ssl.verify
    end

    test "uses custom cert_store when provided and no ssl_ca_file or ssl_ca_path" do
      custom_store = OpenSSL::X509::Store.new
      connection = SourceMonitor::HTTP.client(cert_store: custom_store)

      assert_equal custom_store, connection.ssl.cert_store
    end

    test "ignores cert_store when ssl_ca_file is configured" do
      SourceMonitor.configure do |config|
        config.http.ssl_ca_file = "/path/to/custom/ca.pem"
      end

      custom_store = OpenSSL::X509::Store.new
      connection = SourceMonitor::HTTP.client(cert_store: custom_store)

      assert_equal "/path/to/custom/ca.pem", connection.ssl.ca_file
      assert_nil connection.ssl.cert_store
    end

    test "fetches and parses gzipped feeds" do
      body = File.read(file_fixture("feeds/rss_sample.xml"))

      stub_request(:get, "https://example.com/feed.rss")
        .to_return(
          status: 200,
          body: gzip(body),
          headers: {
            "Content-Type" => "application/rss+xml",
            "Content-Encoding" => "gzip"
          }
        )

      connection = SourceMonitor::HTTP.client
      response = connection.get("https://example.com/feed.rss")

      assert_equal body, response.body

      feed = Feedjira.parse(response.body)
      assert_equal "Example RSS Feed", feed.title
    end

    private

    def gzip(str)
      buffer = StringIO.new
      Zlib::GzipWriter.wrap(buffer) { |gz| gz.write(str) }
      buffer.string
    end
  end
end
