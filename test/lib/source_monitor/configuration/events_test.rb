# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class EventsTest < ActiveSupport::TestCase
      setup do
        @events = Events.new
      end

      test "registers after_item_created callback" do
        handler = ->(event) { event }
        @events.after_item_created(handler)

        assert_equal [ handler ], @events.callbacks_for(:after_item_created)
      end

      test "registers after_item_scraped callback" do
        handler = ->(event) { event }
        @events.after_item_scraped(handler)

        assert_equal [ handler ], @events.callbacks_for(:after_item_scraped)
      end

      test "registers after_fetch_completed callback with block" do
        @events.after_fetch_completed { |event| event }

        assert_equal 1, @events.callbacks_for(:after_fetch_completed).size
      end

      test "callbacks_for returns empty array for unknown event" do
        assert_equal [], @events.callbacks_for(:nonexistent)
      end

      test "callbacks_for returns duplicate-safe copy" do
        handler = ->(event) { event }
        @events.after_item_created(handler)

        callbacks = @events.callbacks_for(:after_item_created)
        callbacks.clear

        assert_equal 1, @events.callbacks_for(:after_item_created).size
      end

      test "register_item_processor with callable" do
        processor = ->(item) { item }
        result = @events.register_item_processor(processor)

        assert_equal processor, result
        assert_equal [ processor ], @events.item_processors
      end

      test "register_item_processor with block" do
        @events.register_item_processor { |item| item }

        assert_equal 1, @events.item_processors.size
      end

      test "register_item_processor raises for non-callable" do
        assert_raises(ArgumentError) { @events.register_item_processor("not_callable") }
      end

      test "item_processors returns duplicate-safe copy" do
        @events.register_item_processor { |item| item }
        processors = @events.item_processors
        processors.clear

        assert_equal 1, @events.item_processors.size
      end

      test "reset clears callbacks and processors" do
        @events.after_item_created { |e| e }
        @events.register_item_processor { |i| i }

        @events.reset!

        assert_empty @events.callbacks_for(:after_item_created)
        assert_empty @events.item_processors
      end

      test "raises for non-callable callback handler" do
        assert_raises(ArgumentError) { @events.after_item_created("not_callable") }
      end
    end
  end
end
