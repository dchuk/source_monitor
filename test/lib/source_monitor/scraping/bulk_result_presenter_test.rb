# frozen_string_literal: true

require "test_helper"
require "source_monitor/scraping/bulk_result_presenter"

module SourceMonitor
  module Scraping
    class BulkResultPresenterTest < ActiveSupport::TestCase
      def setup
        @pluralizer = ->(count, word) { count == 1 ? "#{count} #{word}" : "#{count} #{word}s" }
      end

      test "success status with enqueued items" do
        result = mock_result(
          status: :success,
          selection: :current,
          enqueued_count: 5,
          already_enqueued_count: 0
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :notice, payload[:flash_key]
        assert_equal :success, payload[:level]
        assert_includes payload[:message], "Queued scraping for 5 items"
        assert_includes payload[:message], "current view"
      end

      test "success status with enqueued and already enqueued items" do
        result = mock_result(
          status: :success,
          selection: :unscraped,
          enqueued_count: 3,
          already_enqueued_count: 2
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :success, payload[:level]
        assert_includes payload[:message], "Queued scraping for 3 items"
        assert_includes payload[:message], "2 items already in progress"
      end

      test "partial status with rate limiting" do
        result = mock_result(
          status: :partial,
          selection: :all,
          enqueued_count: 10,
          already_enqueued_count: 0,
          rate_limited: true,
          failure_details: { rate_limited: 5 }
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :warning, payload[:level]
        assert_includes payload[:message], "Queued 10 items"
        assert_includes payload[:message], "Stopped after reaching the per-source limit"
      end

      test "partial status with rate limiting omits number when limit is nil" do
        # Default max_in_flight_per_source is nil -- message should not include a number
        assert_nil SourceMonitor.config.scraping.max_in_flight_per_source

        result = mock_result(
          status: :partial,
          selection: :all,
          enqueued_count: 8,
          already_enqueued_count: 0,
          rate_limited: true,
          failure_details: { rate_limited: 3 }
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_includes payload[:message], "Stopped after reaching the per-source limit"
        refute_includes payload[:message], "of "
      end

      test "partial status with rate limiting shows number when limit is set" do
        SourceMonitor.configure { |c| c.scraping.max_in_flight_per_source = 10 }

        result = mock_result(
          status: :partial,
          selection: :all,
          enqueued_count: 8,
          already_enqueued_count: 0,
          rate_limited: true,
          failure_details: { rate_limited: 3 }
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_includes payload[:message], "Stopped after reaching the per-source limit of 10"
      end

      test "partial status with mixed failures" do
        result = mock_result(
          status: :partial,
          selection: :current,
          enqueued_count: 5,
          already_enqueued_count: 2,
          rate_limited: false,
          failure_details: { scraping_disabled: 3, rate_limited: 0 }
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :warning, payload[:level]
        assert_includes payload[:message], "Queued 5 items"
        assert_includes payload[:message], "2 items already in progress"
        assert_includes payload[:message], "Skipped"
      end

      test "error status with message" do
        result = mock_result(
          status: :error,
          selection: :current,
          enqueued_count: 0,
          already_enqueued_count: 0,
          messages: [ "Scraping is disabled for this source." ]
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :alert, payload[:flash_key]
        assert_equal :error, payload[:level]
        assert_equal "Scraping is disabled for this source.", payload[:message]
      end

      test "error status with no message" do
        result = mock_result(
          status: :error,
          selection: :unscraped,
          enqueued_count: 0,
          already_enqueued_count: 0,
          messages: []
        )

        presenter = BulkResultPresenter.new(result:, pluralizer: @pluralizer)
        payload = presenter.to_flash_payload

        assert_equal :error, payload[:level]
        assert_equal "No items were queued because nothing matched the selected scope.", payload[:message]
      end

      private

      def mock_result(status:, selection:, enqueued_count:, already_enqueued_count:, rate_limited: false, failure_details: {}, messages: [])
        Struct.new(
          :status,
          :selection,
          :enqueued_count,
          :already_enqueued_count,
          :rate_limited?,
          :failure_details,
          :messages,
          keyword_init: true
        ).new(
          status:,
          selection:,
          enqueued_count:,
          already_enqueued_count:,
          rate_limited?: rate_limited,
          failure_details:,
          messages:
        )
      end
    end
  end
end
