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

      # --- Mock-based tests (no ImageMagick required) ---

      test "call returns nil when MiniMagick is not defined" do
        original = ::MiniMagick
        Object.send(:remove_const, :MiniMagick)

        begin
          assert_nil SvgConverter.call(VALID_SVG, filename: "icon.svg")
        ensure
          Object.const_set(:MiniMagick, original)
        end
      end

      test "call delegates to instance and returns converted hash" do
        fake_image = Minitest::Mock.new
        fake_image.expect(:format, nil, [ "png" ])
        fake_image.expect(:resize, nil, [ "64x64" ])
        fake_image.expect(:to_blob, "\x89PNG fake".b)
        fake_image.expect(:destroy!, nil)

        MiniMagick::Image.stub(:read, fake_image) do
          result = SvgConverter.call(VALID_SVG, filename: "icon.svg")

          assert_not_nil result
          assert_equal "image/png", result[:content_type]
          assert_equal "icon.png", result[:filename]
          assert result[:io].is_a?(StringIO)
        end

        fake_image.verify
      end

      test "call returns nil when to_blob returns empty bytes" do
        fake_image = Minitest::Mock.new
        fake_image.expect(:format, nil, [ "png" ])
        fake_image.expect(:resize, nil, [ "64x64" ])
        fake_image.expect(:to_blob, "")
        fake_image.expect(:destroy!, nil)

        MiniMagick::Image.stub(:read, fake_image) do
          result = SvgConverter.call(VALID_SVG, filename: "icon.svg")
          assert_nil result
        end

        fake_image.verify
      end

      test "call returns nil when to_blob returns nil" do
        fake_image = Minitest::Mock.new
        fake_image.expect(:format, nil, [ "png" ])
        fake_image.expect(:resize, nil, [ "64x64" ])
        fake_image.expect(:to_blob, nil)
        fake_image.expect(:destroy!, nil)

        MiniMagick::Image.stub(:read, fake_image) do
          result = SvgConverter.call(VALID_SVG, filename: "icon.svg")
          assert_nil result
        end

        fake_image.verify
      end

      test "replaces .svg extension with .png in filename via mock" do
        fake_image = Minitest::Mock.new
        fake_image.expect(:format, nil, [ "png" ])
        fake_image.expect(:resize, nil, [ "64x64" ])
        fake_image.expect(:to_blob, "\x89PNG".b)
        fake_image.expect(:destroy!, nil)

        MiniMagick::Image.stub(:read, fake_image) do
          result = SvgConverter.call(VALID_SVG, filename: "favicon.svg")
          assert_equal "favicon.png", result[:filename]
        end

        fake_image.verify
      end

      test "uses custom size parameter via mock" do
        fake_image = Minitest::Mock.new
        fake_image.expect(:format, nil, [ "png" ])
        fake_image.expect(:resize, nil, [ "128x128" ])
        fake_image.expect(:to_blob, "\x89PNG".b)
        fake_image.expect(:destroy!, nil)

        MiniMagick::Image.stub(:read, fake_image) do
          result = SvgConverter.call(VALID_SVG, filename: "icon.svg", size: 128)
          assert_not_nil result
          assert_equal "image/png", result[:content_type]
        end

        fake_image.verify
      end

      test "call returns nil and logs when conversion raises an error" do
        MiniMagick::Image.stub(:read, ->(*_args) { raise StandardError, "boom" }) do
          result = SvgConverter.call(VALID_SVG, filename: "icon.svg")
          assert_nil result
        end
      end

      test "log_conversion_failure logs warning via Rails.logger" do
        converter = SvgConverter.new(VALID_SVG, filename: "icon.svg", size: 64)
        error = StandardError.new("test error")

        mock_logger = Minitest::Mock.new
        mock_logger.expect(:warn, nil, [ String ])

        Rails.stub(:logger, mock_logger) do
          converter.send(:log_conversion_failure, error)
        end

        assert mock_logger.verify
      end

      test "log_conversion_failure does nothing when Rails.logger is nil" do
        converter = SvgConverter.new(VALID_SVG, filename: "icon.svg", size: 64)
        error = StandardError.new("test error")

        Rails.stub(:logger, nil) do
          assert_nil converter.send(:log_conversion_failure, error)
        end
      end

      # --- Tests that require ImageMagick ---

      test "converts valid SVG to PNG" do
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

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
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

        result = SvgConverter.call(VALID_SVG, filename: "favicon.svg")

        assert_not_nil result
        assert_equal "favicon.png", result[:filename]
      end

      test "preserves non-svg filename and adds no extension change" do
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

        result = SvgConverter.call(VALID_SVG, filename: "icon.png")

        assert_not_nil result
        assert_equal "icon.png", result[:filename]
      end

      test "returns nil for invalid SVG content" do
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

        result = SvgConverter.call("not valid svg at all", filename: "bad.svg")

        assert_nil result
      end

      test "uses custom size parameter" do
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

        result = SvgConverter.call(VALID_SVG, filename: "icon.svg", size: 128)

        assert_not_nil result
        assert_equal "image/png", result[:content_type]
      end

      test "returns nil for empty SVG body" do
        skip "ImageMagick not available" unless system("which convert > /dev/null 2>&1")

        result = SvgConverter.call("", filename: "empty.svg")

        assert_nil result
      end
    end
  end
end
