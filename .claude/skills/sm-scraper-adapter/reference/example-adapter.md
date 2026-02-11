# Example Scraper Adapter

A complete working example of a custom scraper adapter.

## Use Case

This adapter extracts content from pages that require API-based rendering (e.g., JavaScript-heavy sites that need a headless browser service).

## Implementation

```ruby
# app/scrapers/my_app/scrapers/headless.rb
module MyApp
  module Scrapers
    class Headless < SourceMonitor::Scrapers::Base
      # Default settings for this adapter.
      # Overridable per-source via source.scrape_settings JSON column,
      # or per-invocation via the settings parameter.
      def self.default_settings
        {
          render_service_url: ENV.fetch("RENDER_SERVICE_URL", "http://localhost:3001/render"),
          wait_for_selector: "body",
          timeout: 30,
          selectors: {
            content: "article, main, .content",
            title: "h1, title"
          }
        }
      end

      def call
        url = preferred_url
        return missing_url_result unless url.present?

        # Step 1: Render the page via headless service
        render_result = render_page(url)
        return fetch_failure(render_result) unless render_result[:success]

        html = render_result[:body]

        # Step 2: Extract content using CSS selectors
        content = extract_content(html)
        title = extract_title(html)

        if content.blank?
          return Result.new(
            status: :partial,
            html: html,
            content: nil,
            metadata: build_metadata(url: url, title: title, note: "No content extracted")
          )
        end

        Result.new(
          status: :success,
          html: html,
          content: content,
          metadata: build_metadata(url: url, title: title)
        )
      rescue Faraday::TimeoutError => error
        timeout_result(url, error)
      rescue StandardError => error
        error_result(url, error)
      end

      private

      def preferred_url
        item.canonical_url.presence || item.url
      end

      def render_page(url)
        conn = http.client(timeout: settings[:timeout])
        response = conn.post(settings[:render_service_url]) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            url: url,
            wait_for: settings[:wait_for_selector],
            timeout: (settings[:timeout].to_i * 1000)
          }.to_json
        end

        if response.status >= 200 && response.status < 300
          { success: true, body: response.body, status: response.status }
        else
          { success: false, status: response.status, error: "HTTP #{response.status}" }
        end
      rescue Faraday::Error => error
        { success: false, error: error.message }
      end

      def extract_content(html)
        return nil if html.blank?

        doc = Nokogiri::HTML(html)
        selector = settings.dig(:selectors, :content) || "body"

        element = doc.at_css(selector)
        return nil unless element

        # Remove script and style tags
        element.css("script, style, nav, footer, header").each(&:remove)
        element.text.squeeze(" \n").strip
      end

      def extract_title(html)
        return nil if html.blank?

        doc = Nokogiri::HTML(html)
        selector = settings.dig(:selectors, :title) || "title"
        doc.at_css(selector)&.text&.strip
      end

      def build_metadata(url:, title: nil, note: nil)
        meta = {
          url: url,
          extraction_method: "headless",
          title: title
        }
        meta[:note] = note if note
        meta.compact
      end

      def missing_url_result
        Result.new(
          status: :failed,
          metadata: { error: "missing_url", message: "No URL available for scraping" }
        )
      end

      def fetch_failure(render_result)
        Result.new(
          status: :failed,
          metadata: {
            error: "render_failed",
            message: render_result[:error] || "Render service returned error",
            http_status: render_result[:status]
          }.compact
        )
      end

      def timeout_result(url, error)
        Result.new(
          status: :failed,
          metadata: {
            error: "timeout",
            message: error.message,
            url: url
          }
        )
      end

      def error_result(url, error)
        Result.new(
          status: :failed,
          metadata: {
            error: error.class.name,
            message: error.message,
            url: url
          }
        )
      end
    end
  end
end
```

## Registration

```ruby
# config/initializers/source_monitor.rb
SourceMonitor.configure do |config|
  config.scrapers.register(:headless, "MyApp::Scrapers::Headless")
end
```

## Per-Source Settings

Override adapter defaults via the source's `scrape_settings` JSON column:

```ruby
source = SourceMonitor::Source.find(1)
source.update!(scrape_settings: {
  render_service_url: "https://render.example.com/api/render",
  wait_for_selector: ".article-content",
  timeout: 60,
  selectors: {
    content: ".article-body",
    title: ".article-title h1"
  }
})
```

## Tests

```ruby
require "test_helper"
require "webmock/minitest"

class HeadlessScraperTest < ActiveSupport::TestCase
  setup do
    @source = create_source!
    @item = @source.items.create!(
      title: "Test Article",
      url: "https://example.com/spa-article",
      external_id: "headless-test-1"
    )
  end

  test "successfully renders and extracts content" do
    stub_request(:post, "http://localhost:3001/render")
      .to_return(
        status: 200,
        body: <<~HTML
          <html>
            <head><title>Test Page</title></head>
            <body>
              <article>
                <h1>Article Title</h1>
                <p>This is the article content.</p>
              </article>
            </body>
          </html>
        HTML
      )

    result = MyApp::Scrapers::Headless.call(item: @item, source: @source)

    assert_equal :success, result.status
    assert_includes result.content, "article content"
    assert_equal "headless", result.metadata[:extraction_method]
  end

  test "returns failed when render service is down" do
    stub_request(:post, "http://localhost:3001/render")
      .to_return(status: 500, body: "Internal Server Error")

    result = MyApp::Scrapers::Headless.call(item: @item, source: @source)

    assert_equal :failed, result.status
    assert_equal "render_failed", result.metadata[:error]
  end

  test "returns partial when no content found" do
    stub_request(:post, "http://localhost:3001/render")
      .to_return(status: 200, body: "<html><body><nav>Nav only</nav></body></html>")

    result = MyApp::Scrapers::Headless.call(item: @item, source: @source)

    assert_equal :partial, result.status
    assert_nil result.content
  end

  test "handles missing URL" do
    @item.update!(url: nil)

    result = MyApp::Scrapers::Headless.call(item: @item, source: @source)

    assert_equal :failed, result.status
    assert_equal "missing_url", result.metadata[:error]
  end

  test "merges source-level settings" do
    @source.update!(scrape_settings: { timeout: 60 })

    stub_request(:post, "http://localhost:3001/render")
      .to_return(status: 200, body: "<html><body><article>Content</article></body></html>")

    result = MyApp::Scrapers::Headless.call(item: @item, source: @source)

    assert_equal :success, result.status
  end
end
```
