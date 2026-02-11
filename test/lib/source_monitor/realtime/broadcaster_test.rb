# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Realtime
    class BroadcasterTest < ActiveSupport::TestCase
      setup do
        # Reset the Broadcaster setup state and memoized callbacks
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@setup, nil)
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@fetch_callback, nil)
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@item_callback, nil)
      end

      teardown do
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@setup, nil)
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@fetch_callback, nil)
        SourceMonitor::Realtime::Broadcaster.instance_variable_set(:@item_callback, nil)
      end

      # --- Task 3: setup!, broadcast_source, broadcast_item ---

      test "setup! registers event callbacks when turbo is available" do
        assert defined?(Turbo::StreamsChannel), "Turbo::StreamsChannel should be defined in test env"

        SourceMonitor::Realtime::Broadcaster.setup!

        fetch_callbacks = SourceMonitor.config.events.callbacks_for(:after_fetch_completed)
        item_callbacks = SourceMonitor.config.events.callbacks_for(:after_item_scraped)

        assert fetch_callbacks.any? { |cb| cb.is_a?(Proc) }, "fetch callback should be registered"
        assert item_callbacks.any? { |cb| cb.is_a?(Proc) }, "item callback should be registered"
      end

      test "setup! does not register callbacks twice" do
        SourceMonitor::Realtime::Broadcaster.setup!

        fetch_count_before = SourceMonitor.config.events.callbacks_for(:after_fetch_completed).size
        item_count_before = SourceMonitor.config.events.callbacks_for(:after_item_scraped).size

        SourceMonitor::Realtime::Broadcaster.setup!

        fetch_count_after = SourceMonitor.config.events.callbacks_for(:after_fetch_completed).size
        item_count_after = SourceMonitor.config.events.callbacks_for(:after_item_scraped).size

        assert_equal fetch_count_before, fetch_count_after
        assert_equal item_count_before, item_count_after
      end

      test "setup! skips when turbo is not available" do
        SourceMonitor::Realtime::Broadcaster.stub(:turbo_available?, false) do
          SourceMonitor::Realtime::Broadcaster.setup!
        end

        # Since turbo_available? returned false, @setup should still be nil
        refute SourceMonitor::Realtime::Broadcaster.instance_variable_get(:@setup)
      end

      test "broadcast_source does nothing when turbo is unavailable" do
        source = create_source!

        SourceMonitor::Realtime::Broadcaster.stub(:turbo_available?, false) do
          SourceMonitor::Realtime::Broadcaster.broadcast_source(source)
        end

        pass
      end

      test "broadcast_source calls broadcast_source_row and broadcast_source_show" do
        source = create_source!
        row_called = false
        show_called = false

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source_row, ->(_s) { row_called = true }) do
          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source_show, ->(_s) { show_called = true }) do
            SourceMonitor::Realtime::Broadcaster.broadcast_source(source)
          end
        end

        assert row_called, "broadcast_source_row should have been called"
        assert show_called, "broadcast_source_show should have been called"
      end

      test "broadcast_source returns nil when record cannot be reloaded" do
        source = create_source!
        source.destroy!

        SourceMonitor::Realtime::Broadcaster.broadcast_source(source)

        pass
      end

      test "broadcast_item does nothing when turbo is unavailable" do
        source = create_source!
        item = create_item!(source:)

        SourceMonitor::Realtime::Broadcaster.stub(:turbo_available?, false) do
          SourceMonitor::Realtime::Broadcaster.broadcast_item(item)
        end

        pass
      end

      test "broadcast_item calls Turbo::StreamsChannel.broadcast_replace_to" do
        source = create_source!
        item = create_item!(source:, scrape_status: "success")

        broadcast_called = false
        mock_broadcast = lambda { |*_args, **_kwargs|
          broadcast_called = true
        }

        Turbo::StreamsChannel.stub(:broadcast_replace_to, mock_broadcast) do
          SourceMonitor::ItemsController.stub(:render, "<div>rendered</div>") do
            SourceMonitor::Realtime::Broadcaster.broadcast_item(item)
          end
        end

        assert broadcast_called, "Turbo::StreamsChannel.broadcast_replace_to should be called"
      end

      test "broadcast_item rescues errors gracefully" do
        source = create_source!
        item = create_item!(source:)

        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_a, **_k) { raise StandardError, "boom" }) do
          SourceMonitor::Realtime::Broadcaster.broadcast_item(item)
        end

        pass
      end

      test "broadcast_item returns nil for nil item after reload" do
        SourceMonitor::Realtime::Broadcaster.stub(:reload_record, ->(_r) { nil }) do
          result = SourceMonitor::Realtime::Broadcaster.broadcast_item(nil)
          assert_nil result
        end
      end

      # --- Task 4: toast broadcasting and event handlers ---

      test "broadcast_toast sends append to notification stream" do
        broadcast_called = false
        captured_target = nil

        mock_broadcast = lambda { |*args, **kwargs|
          broadcast_called = true
          captured_target = kwargs[:target]
        }

        Turbo::StreamsChannel.stub(:broadcast_append_to, mock_broadcast) do
          SourceMonitor::ApplicationController.stub(:render, "<div>toast</div>") do
            SourceMonitor::Realtime::Broadcaster.broadcast_toast(
              message: "Test toast",
              level: :info,
              title: "Notice",
              delay_ms: 3000
            )
          end
        end

        assert broadcast_called, "broadcast_append_to should be called"
        assert_equal SourceMonitor::Realtime::Broadcaster::NOTIFICATION_STREAM, captured_target
      end

      test "broadcast_toast does nothing when turbo unavailable" do
        SourceMonitor::Realtime::Broadcaster.stub(:turbo_available?, false) do
          SourceMonitor::Realtime::Broadcaster.broadcast_toast(message: "ignored")
        end

        pass
      end

      test "broadcast_toast does nothing when message is blank" do
        broadcast_called = false
        Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*_a, **_k) { broadcast_called = true }) do
          SourceMonitor::Realtime::Broadcaster.broadcast_toast(message: "")
        end
        refute broadcast_called, "should not broadcast when message is blank"

        Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*_a, **_k) { broadcast_called = true }) do
          SourceMonitor::Realtime::Broadcaster.broadcast_toast(message: nil)
        end
        refute broadcast_called, "should not broadcast when message is nil"
      end

      test "broadcast_toast rescues errors gracefully" do
        Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*_a, **_k) { raise StandardError, "fail" }) do
          SourceMonitor::Realtime::Broadcaster.broadcast_toast(message: "test")
        end

        pass
      end

      test "handle_fetch_completed broadcasts source and toast for fetched status" do
        source = create_source!
        processing = Struct.new(:created, :updated).new(5, 2)
        result_obj = Struct.new(:status, :item_processing, :error).new("fetched", processing, nil)
        event = SourceMonitor::Events::FetchCompletedEvent.new(
          source: source,
          result: result_obj,
          status: "fetched",
          occurred_at: Time.current
        )

        source_broadcast_called = false
        toast_broadcast_called = false
        toast_message = nil

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { source_broadcast_called = true }) do
          mock_toast = lambda { |message:, level: nil, title: nil, delay_ms: nil|
            toast_broadcast_called = true
            toast_message = message
          }

          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
            SourceMonitor::Realtime::Broadcaster.send(:handle_fetch_completed, event)
          end
        end

        assert source_broadcast_called, "should broadcast source"
        assert toast_broadcast_called, "should broadcast toast"
        assert_match(/Fetched.*5 created.*2 updated/, toast_message)
      end

      test "handle_fetch_completed broadcasts not_modified toast" do
        source = create_source!
        result_obj = Struct.new(:status, :item_processing, :error).new("not_modified", nil, nil)
        event = SourceMonitor::Events::FetchCompletedEvent.new(
          source: source,
          result: result_obj,
          status: "not_modified",
          occurred_at: Time.current
        )

        toast_message = nil
        toast_level = nil

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { }) do
          mock_toast = lambda { |message:, level: nil, **_rest|
            toast_message = message
            toast_level = level
          }

          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
            SourceMonitor::Realtime::Broadcaster.send(:handle_fetch_completed, event)
          end
        end

        assert_match(/up to date/, toast_message)
        assert_equal :info, toast_level
      end

      test "handle_fetch_completed broadcasts failed toast with error message" do
        source = create_source!
        error_obj = Struct.new(:message).new("Connection timeout")
        result_obj = Struct.new(:status, :item_processing, :error).new("failed", nil, error_obj)
        event = SourceMonitor::Events::FetchCompletedEvent.new(
          source: source,
          result: result_obj,
          status: "failed",
          occurred_at: Time.current
        )

        toast_message = nil
        toast_level = nil

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { }) do
          mock_toast = lambda { |message:, level: nil, **_rest|
            toast_message = message
            toast_level = level
          }

          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
            SourceMonitor::Realtime::Broadcaster.send(:handle_fetch_completed, event)
          end
        end

        assert_match(/Fetch failed/, toast_message)
        assert_match(/Connection timeout/, toast_message)
        assert_equal :error, toast_level
      end

      test "handle_fetch_completed does nothing with nil event" do
        SourceMonitor::Realtime::Broadcaster.send(:handle_fetch_completed, nil)

        pass
      end

      test "handle_item_scraped broadcasts item and source and toast" do
        source = create_source!
        item = create_item!(source:, title: "My Article", scrape_status: "success")
        event = SourceMonitor::Events::ItemScrapedEvent.new(
          item: item,
          source: source,
          result: nil,
          log: nil,
          status: "success",
          occurred_at: Time.current
        )

        item_broadcast_called = false
        source_broadcast_called = false
        toast_message = nil

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_item, ->(_i) { item_broadcast_called = true }) do
          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { source_broadcast_called = true }) do
            mock_toast = lambda { |message:, level: nil, **_rest|
              toast_message = message
            }

            SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
              SourceMonitor::Realtime::Broadcaster.send(:handle_item_scraped, event)
            end
          end
        end

        assert item_broadcast_called
        assert source_broadcast_called
        assert_match(/Scrape completed.*My Article/, toast_message)
      end

      test "handle_item_scraped broadcasts failure toast when status is failed" do
        source = create_source!
        item = create_item!(source:, title: "Bad Article")
        event = SourceMonitor::Events::ItemScrapedEvent.new(
          item: item,
          source: source,
          result: nil,
          log: nil,
          status: "failed",
          occurred_at: Time.current
        )

        toast_message = nil
        toast_level = nil

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_item, ->(_i) { }) do
          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { }) do
            mock_toast = lambda { |message:, level: nil, **_rest|
              toast_message = message
              toast_level = level
            }

            SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
              SourceMonitor::Realtime::Broadcaster.send(:handle_item_scraped, event)
            end
          end
        end

        assert_match(/Scrape failed.*Bad Article/, toast_message)
        assert_equal :error, toast_level
      end

      test "handle_item_scraped does nothing with nil event" do
        SourceMonitor::Realtime::Broadcaster.send(:handle_item_scraped, nil)

        pass
      end

      test "handle_item_scraped falls back to item.source when event.source is nil" do
        source = create_source!
        item = create_item!(source:, title: "Article")
        event = SourceMonitor::Events::ItemScrapedEvent.new(
          item: item,
          source: nil,
          result: nil,
          log: nil,
          status: "success",
          occurred_at: Time.current
        )

        source_broadcast_called = false
        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_item, ->(_i) { }) do
          SourceMonitor::Realtime::Broadcaster.stub(:broadcast_source, ->(_s) { source_broadcast_called = true }) do
            SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, ->(**_k) { }) do
              SourceMonitor::Realtime::Broadcaster.send(:handle_item_scraped, event)
            end
          end
        end

        assert source_broadcast_called
      end

      test "broadcast_item_toast uses Feed item fallback when title is blank" do
        source = create_source!
        item = create_item!(source:, title: nil)
        event = SourceMonitor::Events::ItemScrapedEvent.new(
          item: item,
          source: source,
          result: nil,
          log: nil,
          status: "success",
          occurred_at: Time.current
        )

        toast_message = nil
        mock_toast = lambda { |message:, level: nil, **_rest|
          toast_message = message
        }

        SourceMonitor::Realtime::Broadcaster.stub(:broadcast_toast, mock_toast) do
          SourceMonitor::Realtime::Broadcaster.send(:broadcast_item_toast, event)
        end

        assert_match(/Feed item/, toast_message)
      end

      # --- Task 5: helpers ---

      test "reload_record reloads a persisted record" do
        source = create_source!(name: "Original")
        SourceMonitor::Source.where(id: source.id).update_all(name: "Updated")

        reloaded = SourceMonitor::Realtime::Broadcaster.send(:reload_record, source)

        assert_equal "Updated", reloaded.name
      end

      test "reload_record returns nil for nil input" do
        result = SourceMonitor::Realtime::Broadcaster.send(:reload_record, nil)
        assert_nil result
      end

      test "reload_record returns original record when reload fails" do
        source = create_source!
        # Simulate reload failure by stubbing
        source.stub(:reload, -> { raise ActiveRecord::RecordNotFound }) do
          result = SourceMonitor::Realtime::Broadcaster.send(:reload_record, source)
          assert_equal source, result
        end
      end

      test "turbo_available? returns true when Turbo::StreamsChannel is defined" do
        assert SourceMonitor::Realtime::Broadcaster.send(:turbo_available?)
      end

      test "register_callback does not add duplicate callbacks" do
        callback = -> { }
        SourceMonitor::Realtime::Broadcaster.send(:register_callback, :after_fetch_completed, callback)
        SourceMonitor::Realtime::Broadcaster.send(:register_callback, :after_fetch_completed, callback)

        callbacks = SourceMonitor.config.events.callbacks_for(:after_fetch_completed)
        count = callbacks.count { |cb| cb.equal?(callback) }
        assert_equal 1, count, "callback should only be registered once"
      end

      test "log_info writes to Rails logger" do
        logged = false
        mock_logger = Minitest::Mock.new
        mock_logger.expect(:info, nil) { |msg| logged = true; msg.include?("broadcast_test") }

        Rails.stub(:logger, mock_logger) do
          SourceMonitor::Realtime::Broadcaster.send(:log_info, "broadcast_test", source_id: 1)
        end

        assert logged, "should have logged info message"
        mock_logger.verify
      end

      test "log_info silently handles errors" do
        bad_logger = Object.new
        def bad_logger.info(_msg)
          raise "logger broken"
        end

        Rails.stub(:logger, bad_logger) do
          result = SourceMonitor::Realtime::Broadcaster.send(:log_info, "test")
          assert_nil result
        end
      end

      test "log_error writes error to Rails logger" do
        logged_message = nil
        mock_logger = Object.new
        mock_logger.define_singleton_method(:error) { |msg| logged_message = msg }

        error = StandardError.new("test error")

        Rails.stub(:logger, mock_logger) do
          SourceMonitor::Realtime::Broadcaster.send(:log_error, "test context", error)
        end

        assert_match(/Realtime test context failed/, logged_message)
        assert_match(/test error/, logged_message)
      end

      test "log_error silently handles its own errors" do
        bad_logger = Object.new
        def bad_logger.error(_msg)
          raise "logger broken"
        end

        Rails.stub(:logger, bad_logger) do
          result = SourceMonitor::Realtime::Broadcaster.send(
            :log_error, "test", StandardError.new("oops")
          )
          assert_nil result
        end
      end

      test "fetch_callback and item_callback return stable lambda references" do
        cb1 = SourceMonitor::Realtime::Broadcaster.fetch_callback
        cb2 = SourceMonitor::Realtime::Broadcaster.fetch_callback
        assert_same cb1, cb2, "fetch_callback should be memoized"

        icb1 = SourceMonitor::Realtime::Broadcaster.item_callback
        icb2 = SourceMonitor::Realtime::Broadcaster.item_callback
        assert_same icb1, icb2, "item_callback should be memoized"
      end

      test "broadcast_source_row rescues errors" do
        source = create_source!

        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_a, **_k) { raise "boom" }) do
          SourceMonitor::Realtime::Broadcaster.send(:broadcast_source_row, source)
        end

        pass
      end

      test "broadcast_source_show rescues errors" do
        source = create_source!

        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_a, **_k) { raise "boom" }) do
          SourceMonitor::Realtime::Broadcaster.send(:broadcast_source_show, source)
        end

        pass
      end

      private

      def create_item!(source:, **attrs)
        SourceMonitor::Item.create!(
          {
            source:,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex(6)}",
            title: "Example Item"
          }.merge(attrs)
        )
      end
    end
  end
end
