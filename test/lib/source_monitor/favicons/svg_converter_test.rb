# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Favicons
    class SvgConverterTest < ActiveSupport::TestCase
      VALID_SVG = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
          <rect width="32" height="32" fill="red"/>
        </svg>
      SVG

      setup do
        SourceMonitor.reset_configuration!
      end

      test "converts valid SVG to PNG" do
        result = SvgConverter.call(VALID_SVG, filename: "icon.svg")

        assert_not_nil result
        assert_equal "image/png", result[:content_type]
        assert_equal "icon.png", result[:filename]
        assert result[:io].is_a?(StringIO)

        png_bytes = result[:io].read
        assert png_bytes.start_with?("\x89PNG".b)
        assert png_bytes.bytesize > 0
      end

      test "replaces .svg extension with .png in filename" do
        result = SvgConverter.call(VALID_SVG, filename: "favicon.svg")

        assert_not_nil result
        assert_equal "favicon.png", result[:filename]
      end

      test "preserves non-svg filename and adds no extension change" do
        result = SvgConverter.call(VALID_SVG, filename: "icon.png")

        assert_not_nil result
        assert_equal "icon.png", result[:filename]
      end

      test "returns nil for invalid SVG content" do
        result = SvgConverter.call("not valid svg at all", filename: "bad.svg")

        assert_nil result
      end

      test "returns nil when MiniMagick is not defined" do
        # Temporarily hide MiniMagick constant
        Object.send(:remove_const, :MiniMagick) if defined?(::MiniMagick)
        mini_magick_mod = nil

        begin
          # We already removed it above, but the autoload might reload it
          # Just test the guard directly
          assert_nil SvgConverter.call(VALID_SVG, filename: "icon.svg")
        ensure
          require "mini_magick"
        end
      end

      test "uses custom size parameter" do
        result = SvgConverter.call(VALID_SVG, filename: "icon.svg", size: 128)

        assert_not_nil result
        assert_equal "image/png", result[:content_type]
      end

      test "returns nil for empty SVG body" do
        result = SvgConverter.call("", filename: "empty.svg")

        assert_nil result
      end
    end
  end
end
