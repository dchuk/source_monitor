# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Images
    class ContentRewriterTest < ActiveSupport::TestCase
      # =========================================================================
      # image_urls extraction
      # =========================================================================

      test "image_urls returns empty array for nil HTML" do
        rewriter = ContentRewriter.new(nil)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls returns empty array for blank HTML" do
        rewriter = ContentRewriter.new("")
        assert_equal [], rewriter.image_urls
      end

      test "image_urls extracts single img src URL" do
        html = '<p>Hello</p><img src="https://example.com/photo.jpg">'
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/photo.jpg"], rewriter.image_urls
      end

      test "image_urls extracts multiple img src URLs" do
        html = <<~HTML
          <img src="https://example.com/a.jpg">
          <img src="https://example.com/b.png">
        HTML
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/a.jpg", "https://example.com/b.png"], rewriter.image_urls
      end

      test "image_urls deduplicates identical URLs" do
        html = <<~HTML
          <img src="https://example.com/a.jpg">
          <img src="https://example.com/a.jpg">
        HTML
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/a.jpg"], rewriter.image_urls
      end

      test "image_urls skips data URIs" do
        html = '<img src="data:image/png;base64,iVBORw0KGgo=">'
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls skips img tags without src attribute" do
        html = "<img alt='no source'>"
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls skips blank src attributes" do
        html = '<img src="">'
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls resolves relative URLs when base_url provided" do
        html = '<img src="/images/photo.jpg">'
        rewriter = ContentRewriter.new(html, base_url: "https://example.com/articles/123")
        assert_equal ["https://example.com/images/photo.jpg"], rewriter.image_urls
      end

      test "image_urls skips relative URLs when no base_url provided" do
        html = '<img src="/images/photo.jpg">'
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls handles malformed URLs gracefully" do
        html = '<img src="ht tp://bad url.com/img.jpg">'
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls returns empty array for HTML with no images" do
        html = "<p>Just text</p><div>More content</div>"
        rewriter = ContentRewriter.new(html)
        assert_equal [], rewriter.image_urls
      end

      test "image_urls works with self-closing img tags" do
        html = '<img src="https://example.com/photo.jpg" />'
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/photo.jpg"], rewriter.image_urls
      end

      test "image_urls handles relative path resolution" do
        html = '<img src="photo.jpg">'
        rewriter = ContentRewriter.new(html, base_url: "https://example.com/blog/post/")
        assert_equal ["https://example.com/blog/post/photo.jpg"], rewriter.image_urls
      end

      # =========================================================================
      # rewrite
      # =========================================================================

      test "rewrite returns original HTML when no img tags present" do
        html = "<p>Hello world</p>"
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |_url| "https://cdn.example.com/replaced.jpg" }
        assert_includes result, "Hello world"
      end

      test "rewrite returns original HTML when HTML is blank" do
        rewriter = ContentRewriter.new("")
        result = rewriter.rewrite { |_url| "https://cdn.example.com/replaced.jpg" }
        assert_equal "", result
      end

      test "rewrite replaces img src with block return value" do
        html = '<img src="https://example.com/photo.jpg">'
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |_url| "https://cdn.example.com/replaced.jpg" }
        assert_includes result, 'src="https://cdn.example.com/replaced.jpg"'
        assert_not_includes result, "example.com/photo.jpg"
      end

      test "rewrite preserves original URL when block returns nil" do
        html = '<img src="https://example.com/photo.jpg">'
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |_url| nil }
        assert_includes result, "https://example.com/photo.jpg"
      end

      test "rewrite preserves original URL when block returns empty string" do
        html = '<img src="https://example.com/photo.jpg">'
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |_url| "" }
        assert_includes result, "https://example.com/photo.jpg"
      end

      test "rewrite handles multiple img tags" do
        html = <<~HTML
          <img src="https://example.com/a.jpg">
          <img src="https://example.com/b.png">
        HTML
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |url| url.gsub("example.com", "cdn.example.com") }
        assert_includes result, "cdn.example.com/a.jpg"
        assert_includes result, "cdn.example.com/b.png"
      end

      test "rewrite preserves other img attributes" do
        html = '<img src="https://example.com/photo.jpg" alt="A photo" class="responsive" width="400">'
        rewriter = ContentRewriter.new(html)
        result = rewriter.rewrite { |_url| "https://cdn.example.com/new.jpg" }
        assert_includes result, 'alt="A photo"'
        assert_includes result, 'class="responsive"'
        assert_includes result, 'width="400"'
      end

      test "rewrite skips data URIs and does not yield them" do
        html = '<img src="data:image/png;base64,abc123"><img src="https://example.com/photo.jpg">'
        yielded_urls = []
        rewriter = ContentRewriter.new(html)
        rewriter.rewrite do |url|
          yielded_urls << url
          "https://cdn.example.com/new.jpg"
        end
        assert_equal ["https://example.com/photo.jpg"], yielded_urls
      end

      test "rewrite handles mixed downloadable and non-downloadable URLs" do
        html = <<~HTML
          <img src="data:image/gif;base64,R0lGODlh">
          <img src="https://example.com/real.jpg">
          <img src="">
        HTML
        yielded_urls = []
        rewriter = ContentRewriter.new(html)
        rewriter.rewrite do |url|
          yielded_urls << url
          "https://cdn.example.com/replaced.jpg"
        end
        assert_equal ["https://example.com/real.jpg"], yielded_urls
      end

      # =========================================================================
      # Edge cases
      # =========================================================================

      test "handles HTML fragments without full document structure" do
        html = '<div><img src="https://example.com/photo.jpg"><span>text</span></div>'
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/photo.jpg"], rewriter.image_urls
      end

      test "handles srcset attribute does not affect image_urls" do
        html = '<img src="https://example.com/photo.jpg" srcset="https://example.com/photo-2x.jpg 2x">'
        rewriter = ContentRewriter.new(html)
        # Only src is extracted, not srcset
        assert_equal ["https://example.com/photo.jpg"], rewriter.image_urls
      end

      test "rewrite with base_url resolves relative URLs before yielding" do
        html = '<img src="/images/photo.jpg">'
        rewriter = ContentRewriter.new(html, base_url: "https://example.com")
        yielded_urls = []
        rewriter.rewrite do |url|
          yielded_urls << url
          "https://cdn.example.com/new.jpg"
        end
        assert_equal ["https://example.com/images/photo.jpg"], yielded_urls
      end

      test "image_urls handles whitespace in src" do
        html = '<img src="  https://example.com/photo.jpg  ">'
        rewriter = ContentRewriter.new(html)
        assert_equal ["https://example.com/photo.jpg"], rewriter.image_urls
      end
    end
  end
end
