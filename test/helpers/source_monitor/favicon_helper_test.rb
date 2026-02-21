# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FaviconHelperTest < ActionView::TestCase
    include SourceMonitor::ApplicationHelper

    setup do
      SourceMonitor.reset_configuration!
    end

    test "source_favicon_tag renders placeholder span when no favicon attached" do
      source = SourceMonitor::Source.new(name: "Example Blog")

      result = source_favicon_tag(source)

      assert_includes result, "<span"
      assert_includes result, "E"
      assert_includes result, 'aria-hidden="true"'
    end

    test "source_favicon_tag placeholder uses first letter uppercased" do
      source = SourceMonitor::Source.new(name: "my source")

      result = source_favicon_tag(source)

      assert_includes result, ">M<"
    end

    test "source_favicon_tag placeholder shows question mark for blank name" do
      source = SourceMonitor::Source.new(name: "")

      result = source_favicon_tag(source)

      assert_includes result, ">?<"
    end

    test "source_favicon_tag placeholder shows question mark for nil name" do
      source = SourceMonitor::Source.new(name: nil)

      result = source_favicon_tag(source)

      assert_includes result, ">?<"
    end

    test "source_favicon_tag generates consistent color from source name" do
      source = SourceMonitor::Source.new(name: "Consistent Name")

      result1 = source_favicon_tag(source)
      result2 = source_favicon_tag(source)

      assert_equal result1, result2

      hue = "Consistent Name".bytes.sum % 360
      assert_includes result1, "hsl(#{hue}, 45%, 65%)"
    end

    test "source_favicon_tag generates different colors for different names" do
      source_a = SourceMonitor::Source.new(name: "Alpha Blog")
      source_b = SourceMonitor::Source.new(name: "Beta Feed")

      result_a = source_favicon_tag(source_a)
      result_b = source_favicon_tag(source_b)

      hue_a = "Alpha Blog".bytes.sum % 360
      hue_b = "Beta Feed".bytes.sum % 360

      assert_not_equal hue_a, hue_b
      assert_includes result_a, "hsl(#{hue_a}, 45%, 65%)"
      assert_includes result_b, "hsl(#{hue_b}, 45%, 65%)"
    end

    test "source_favicon_tag with custom size applies correct dimensions" do
      source = SourceMonitor::Source.new(name: "Sized Source")

      result = source_favicon_tag(source, size: 40)

      assert_includes result, "width: 40px"
      assert_includes result, "height: 40px"
      assert_includes result, "font-size: 20px"
      assert_includes result, "line-height: 40px"
    end

    test "source_favicon_tag default size is 24" do
      source = SourceMonitor::Source.new(name: "Default Size")

      result = source_favicon_tag(source)

      assert_includes result, "width: 24px"
      assert_includes result, "height: 24px"
      assert_includes result, "font-size: 12px"
    end

    test "source_favicon_tag passes additional CSS class" do
      source = SourceMonitor::Source.new(name: "Classy")

      result = source_favicon_tag(source, class: "mr-2")

      assert_includes result, "mr-2"
    end

    test "favicon_attached? returns false when source does not respond to favicon" do
      source = Struct.new(:name).new("No Favicon Method")

      refute send(:favicon_attached?, source)
    end

    test "favicon_attached? returns false when favicon is not attached" do
      source = SourceMonitor::Source.new(name: "Unattached")

      refute send(:favicon_attached?, source)
    end

    test "source_favicon_tag placeholder includes title attribute with source name" do
      source = SourceMonitor::Source.new(name: "My Feed")

      result = source_favicon_tag(source)

      assert_includes result, 'title="My Feed"'
    end

    test "source_favicon_tag placeholder has correct CSS classes for styling" do
      source = SourceMonitor::Source.new(name: "Styled")

      result = source_favicon_tag(source)

      assert_includes result, "inline-flex"
      assert_includes result, "items-center"
      assert_includes result, "justify-center"
      assert_includes result, "rounded-full"
      assert_includes result, "text-white"
      assert_includes result, "font-semibold"
    end
  end
end
