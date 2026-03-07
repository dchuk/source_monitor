# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class PaginationHelperTest < ActionView::TestCase
    include SourceMonitor::ApplicationHelper

    test "single page returns [1]" do
      assert_equal [ 1 ], pagination_page_numbers(current_page: 1, total_pages: 1)
    end

    test "small range shows all pages without gaps" do
      assert_equal [ 1, 2, 3, 4, 5 ], pagination_page_numbers(current_page: 1, total_pages: 5)
      assert_equal [ 1, 2, 3, 4, 5 ], pagination_page_numbers(current_page: 3, total_pages: 5)
      assert_equal [ 1, 2, 3, 4, 5 ], pagination_page_numbers(current_page: 5, total_pages: 5)
    end

    test "large range with current at start" do
      result = pagination_page_numbers(current_page: 1, total_pages: 20)

      assert_equal [ 1, 2, 3, :gap, 20 ], result
    end

    test "large range with current at end" do
      result = pagination_page_numbers(current_page: 20, total_pages: 20)

      assert_equal [ 1, :gap, 18, 19, 20 ], result
    end

    test "large range with current in middle" do
      result = pagination_page_numbers(current_page: 10, total_pages: 20)

      assert_equal [ 1, :gap, 8, 9, 10, 11, 12, :gap, 20 ], result
    end

    test "current near start with gap only on right" do
      result = pagination_page_numbers(current_page: 3, total_pages: 20)

      assert_equal [ 1, 2, 3, 4, 5, :gap, 20 ], result
    end

    test "current near end with gap only on left" do
      result = pagination_page_numbers(current_page: 18, total_pages: 20)

      assert_equal [ 1, :gap, 16, 17, 18, 19, 20 ], result
    end

    test "custom window size" do
      result = pagination_page_numbers(current_page: 5, total_pages: 10, window: 1)

      assert_equal [ 1, :gap, 4, 5, 6, :gap, 10 ], result
    end
  end
end
