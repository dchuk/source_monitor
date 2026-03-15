# frozen_string_literal: true

require "test_helper"
require "view_component/test_helpers"
require "view_component/test_case"

module SourceMonitor
  class IconComponentTest < ViewComponent::TestCase
    test "renders menu_dots icon as SVG" do
      render_inline(IconComponent.new(:menu_dots))

      assert_selector "svg"
      assert_selector "svg path"
    end

    test "renders refresh icon as SVG" do
      render_inline(IconComponent.new(:refresh))

      assert_selector "svg"
      assert_selector "svg path"
    end

    test "renders chevron_down icon as SVG" do
      render_inline(IconComponent.new(:chevron_down))

      assert_selector "svg"
      assert_selector "svg path"
    end

    test "renders external_link icon as SVG" do
      render_inline(IconComponent.new(:external_link))

      assert_selector "svg"
      assert_selector "svg path"
    end

    test "renders spinner icon as SVG" do
      render_inline(IconComponent.new(:spinner))

      assert_selector "svg"
    end

    test "defaults to md size with h-5 w-5 classes" do
      render_inline(IconComponent.new(:refresh))

      assert_selector "svg.h-5.w-5"
    end

    test "sm size renders h-4 w-4 classes" do
      render_inline(IconComponent.new(:refresh, size: :sm))

      assert_selector "svg.h-4.w-4"
    end

    test "lg size renders h-6 w-6 classes" do
      render_inline(IconComponent.new(:refresh, size: :lg))

      assert_selector "svg.h-6.w-6"
    end

    test "includes aria-hidden attribute" do
      render_inline(IconComponent.new(:refresh))

      assert_selector "svg[aria-hidden='true']"
    end

    test "unknown icon name returns empty string" do
      result = render_inline(IconComponent.new(:nonexistent))

      assert_equal "", result.to_s.strip
    end

    test "spinner icon includes circle and path elements" do
      render_inline(IconComponent.new(:spinner))

      assert_selector "svg circle"
      assert_selector "svg path"
    end

    test "accepts additional css_class" do
      render_inline(IconComponent.new(:refresh, css_class: "text-blue-500"))

      assert_selector "svg.text-blue-500"
    end

    test "menu_dots icon has two path elements" do
      render_inline(IconComponent.new(:menu_dots))

      assert_selector "svg path", count: 2
    end
  end
end
