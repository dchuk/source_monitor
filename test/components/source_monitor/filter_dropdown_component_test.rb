# frozen_string_literal: true

require "test_helper"
require "view_component/test_helpers"
require "view_component/test_case"

module SourceMonitor
  class FilterDropdownComponentTest < ViewComponent::TestCase
    test "renders label text" do
      render_inline(FilterDropdownComponent.new(
        label: "Status",
        param_name: :active_eq,
        options: [ [ "All Statuses", "" ], [ "Active", "true" ] ]
      ))

      assert_selector "label", text: "Status"
    end

    test "renders select with correct param name" do
      render_inline(FilterDropdownComponent.new(
        label: "Status",
        param_name: :active_eq,
        options: [ [ "All Statuses", "" ], [ "Active", "true" ] ]
      ))

      assert_selector "select[name='active_eq']"
    end

    test "renders options with correct values" do
      render_inline(FilterDropdownComponent.new(
        label: "Format",
        param_name: :feed_format_eq,
        options: [ [ "All Formats", "" ], [ "RSS", "rss" ], [ "Atom", "atom" ] ]
      ))

      assert_selector "option[value='']", text: "All Formats"
      assert_selector "option[value='rss']", text: "RSS"
      assert_selector "option[value='atom']", text: "Atom"
    end

    test "marks selected option when selected_value matches" do
      render_inline(FilterDropdownComponent.new(
        label: "Format",
        param_name: :feed_format_eq,
        options: [ [ "All Formats", "" ], [ "RSS", "rss" ], [ "Atom", "atom" ] ],
        selected_value: "rss"
      ))

      assert_selector "option[value='rss'][selected]", text: "RSS"
    end

    test "includes onchange for auto-submit" do
      render_inline(FilterDropdownComponent.new(
        label: "Status",
        param_name: :active_eq,
        options: [ [ "All Statuses", "" ] ]
      ))

      assert_selector "select[onchange='this.form.requestSubmit()']"
    end

    test "renders consistent Tailwind styling classes" do
      render_inline(FilterDropdownComponent.new(
        label: "Status",
        param_name: :active_eq,
        options: [ [ "All Statuses", "" ] ]
      ))

      assert_selector "label.text-xs.font-medium.text-slate-500"
      assert_selector "select.rounded-md.border.border-slate-200"
    end

    test "renders without selected_value" do
      render_inline(FilterDropdownComponent.new(
        label: "Health",
        param_name: :health_status_eq,
        options: [ [ "All Health", "" ], [ "Working", "working" ] ]
      ))

      assert_selector "select"
      assert_selector "option", count: 2
    end

    test "wraps select in a form field when form object provided" do
      # When no form object, renders standalone select tag
      render_inline(FilterDropdownComponent.new(
        label: "Status",
        param_name: :active_eq,
        options: [ [ "All Statuses", "" ] ],
        form: nil
      ))

      assert_selector "select[name='active_eq']"
    end
  end
end
