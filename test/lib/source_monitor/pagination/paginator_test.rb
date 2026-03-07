# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Pagination
    class PaginatorTest < ActiveSupport::TestCase
      setup do
        @source = create_source!
        @items = Array.new(6) do |index|
          SourceMonitor::Item.create!(
            source: @source,
            guid: SecureRandom.uuid,
            url: "https://example.com/articles/#{index}",
            title: "Item #{index}",
            published_at: Time.current - index.hours
          )
        end
      end

      test "paginates relation and reports presence of more records" do
        scope = SourceMonitor::Item.where(source: @source).order(published_at: :desc)
        result = SourceMonitor::Pagination::Paginator.new(scope:, page: 1, per_page: 5).paginate

        assert_equal 5, result.records.size
        assert result.has_next_page?
        refute result.has_previous_page?
        assert_equal 1, result.page
      end

      test "provides total_count and total_pages for relation scope" do
        scope = SourceMonitor::Item.where(source: @source).order(published_at: :desc)
        result = SourceMonitor::Pagination::Paginator.new(scope:, page: 1, per_page: 3).paginate

        assert_equal 6, result.total_count
        assert_equal 2, result.total_pages
      end

      test "provides total_count and total_pages for array scope" do
        array_scope = Array.new(10) { |i| "item_#{i}" }
        result = SourceMonitor::Pagination::Paginator.new(scope: array_scope, page: 1, per_page: 4).paginate

        assert_equal 10, result.total_count
        assert_equal 3, result.total_pages
      end

      test "total_pages is at least 1 for empty scope" do
        empty_scope = SourceMonitor::Item.where(source: @source, guid: "nonexistent")
        result = SourceMonitor::Pagination::Paginator.new(scope: empty_scope, page: 1, per_page: 5).paginate

        assert_equal 0, result.total_count
        assert_equal 1, result.total_pages
      end

      test "total_count does not affect existing pagination behavior" do
        scope = SourceMonitor::Item.where(source: @source).order(published_at: :desc)
        result = SourceMonitor::Pagination::Paginator.new(scope:, page: 1, per_page: 3).paginate

        assert_equal 6, result.total_count
        assert_equal 2, result.total_pages
        assert_equal 3, result.records.size
        assert result.has_next_page?
        refute result.has_previous_page?
        assert_equal 2, result.next_page
        assert_nil result.previous_page
      end

      test "handles out of range and coerces invalid page values" do
        scope = SourceMonitor::Item.where(source: @source).order(published_at: :desc)

        result_page_zero = SourceMonitor::Pagination::Paginator.new(scope:, page: 0, per_page: 3).paginate
        assert_equal 1, result_page_zero.page
        assert_equal 3, result_page_zero.records.size

        result_page_three = SourceMonitor::Pagination::Paginator.new(scope:, page: 3, per_page: 3).paginate
        assert_equal 3, result_page_three.page
        assert_equal 0, result_page_three.records.size
        refute result_page_three.has_next_page?
        assert result_page_three.has_previous_page?
      end
    end
  end
end
