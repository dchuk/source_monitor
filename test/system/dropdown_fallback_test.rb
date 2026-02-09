# frozen_string_literal: true

require "application_system_test_case"

module SourceMonitor
  class DropdownFallbackTest < ApplicationSystemTestCase
    test "dropdown gracefully toggles when transition module is unavailable" do
      visit "/test_support/dropdown_without_dependency"

      assert_selector "[data-controller='dropdown'][data-dropdown-state]"

      within "[data-controller='dropdown']" do
        menu = find("[data-dropdown-target='menu']", visible: :all)
        assert menu[:class].to_s.split.include?("hidden"), "menu should be hidden before toggle"

        click_button "Toggle Menu"
        assert_not menu[:class].to_s.split.include?("hidden"), "menu should be visible after fallback toggle"

        find(:xpath, "//body").click
        assert menu[:class].to_s.split.include?("hidden"), "menu should hide again after clicking outside"
      end
    end
  end
end
