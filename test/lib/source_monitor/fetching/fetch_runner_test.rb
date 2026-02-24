# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "minitest/mock"

module SourceMonitor
  module Fetching
    class FetchRunnerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup { clear_enqueued_jobs }

      test "enqueues scrape jobs for newly created items when auto scrape is enabled" do
        source = create_source(scraping_enabled: true, auto_scrape: true)
        item = SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/#{SecureRandom.hex}",
          title: "Example item"
        )

        processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
          created: 1,
          updated: 0,
          failed: 0,
          items: [ item ],
          errors: [],
          created_items: [ item ],
          updated_items: []
        )
        result = SourceMonitor::Fetching::FeedFetcher::Result.new(
          status: :fetched,
          feed: nil,
          response: nil,
          body: nil,
          item_processing: processing
        )

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) { result }
        end

        assert_enqueued_with(job: SourceMonitor::ScrapeItemJob, args: [ item.id ]) do
          FetchRunner.new(source:, fetcher_class: stub_fetcher).run
        end

        assert_equal "pending", item.reload.scrape_status
      end

      test "enqueue marks source as queued" do
        source = create_source

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          SourceMonitor::FetchFeedJob.stub :perform_later, nil do
            FetchRunner.enqueue(source.id)
          end
        end

        assert_equal "queued", source.reload.fetch_status
      end

      test "run updates fetch status lifecycle for successful fetch" do
        source = create_source

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }

          define_method(:call) do
            SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)
          end
        end

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          FetchRunner.new(source:, fetcher_class: stub_fetcher).run
        end

        source.reload
        assert_equal "idle", source.fetch_status
        assert_not_nil source.last_fetch_started_at
      end

      test "run marks source as failed when fetcher raises" do
        source = create_source

        failing_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) { raise StandardError, "boom" }
        end

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          assert_raises(StandardError) do
            FetchRunner.new(source:, fetcher_class: failing_fetcher).run
          end
        end

        assert_equal "failed", source.reload.fetch_status
      end

      test "does not enqueue scrape jobs when auto scrape is disabled" do
        source = create_source(scraping_enabled: true, auto_scrape: false)
        item = SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/#{SecureRandom.hex}",
          title: "Example item"
        )

        processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
          created: 1,
          updated: 0,
          failed: 0,
          items: [ item ],
          errors: [],
          created_items: [ item ],
          updated_items: []
        )
        result = SourceMonitor::Fetching::FeedFetcher::Result.new(
          status: :fetched,
          feed: nil,
          response: nil,
          body: nil,
          item_processing: processing
        )

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) { result }
        end

        assert_no_enqueued_jobs only: SourceMonitor::ScrapeItemJob do
          FetchRunner.new(source:, fetcher_class: stub_fetcher).run
        end

        assert_nil item.reload.scrape_status
      end

      test "raises concurrency error when advisory lock acquisition fails" do
        source = create_source

        failing_lock_class = Class.new do
          def initialize(namespace:, key:, connection_pool:); end

          def with_lock
            raise SourceMonitor::Fetching::AdvisoryLock::NotAcquiredError, "busy"
          end
        end

        runner = FetchRunner.new(
          source:,
          fetcher_class: DummyFetcher,
          lock_factory: failing_lock_class
        )

        assert_raises(FetchRunner::ConcurrencyError) { runner.run }
      end

      test "invokes retention pruner after each fetch run" do
        source = create_source

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }

          define_method(:call) do
            SourceMonitor::Fetching::FeedFetcher::Result.new(status: :not_modified)
          end
        end

        retention_spy = Class.new do
          class << self
            attr_accessor :calls
          end

          def self.call(source:, **)
            self.calls ||= []
            self.calls << source
            nil
          end
        end
        retention_spy.calls = []

        runner = FetchRunner.new(
          source:,
          fetcher_class: stub_fetcher,
          retention_pruner_class: retention_spy
        )

        runner.run

        assert_equal [ source ], retention_spy.calls
      end

      test "delegates completion to injected handlers" do
        source = create_source

        processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
          created: 0,
          updated: 0,
          failed: 0,
          items: [],
          errors: [],
          created_items: [],
          updated_items: []
        )
        result = SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched, item_processing: processing)

        result = SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched, item_processing: processing)

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) { result }
        end

        retention_handler = HandlerSpy.new
        follow_up_handler = HandlerSpy.new
        event_publisher = HandlerSpy.new

        runner = FetchRunner.new(
          source:,
          fetcher_class: stub_fetcher,
          retention_handler: retention_handler,
          follow_up_handler: follow_up_handler,
          event_publisher: event_publisher
        )

        runner.run

        assert_equal 1, retention_handler.calls.count
        assert_equal({ source:, result: result }, retention_handler.calls.first)

        assert_equal 1, follow_up_handler.calls.count
        assert_equal({ source:, result: result }, follow_up_handler.calls.first)

        assert_equal 1, event_publisher.calls.count
        assert_equal({ source:, result: result }, event_publisher.calls.first)
      end

      test "schedules retry according to timeout policy" do
        source = create_source
        error = SourceMonitor::Fetching::TimeoutError.new("timeout")
        stub_fetcher = build_timeout_failure_fetcher(error)

        travel_to Time.zone.parse("2025-10-11 09:00:00 UTC") do
          SourceMonitor::Realtime.stub :broadcast_source, nil do
            assert_enqueued_jobs 1 do
              FetchRunner.new(source:, fetcher_class: stub_fetcher).run
            end
          end

          enqueued = enqueued_jobs.last
          assert_in_delta 2.minutes.from_now.to_f, enqueued[:at], 1.0
          assert_equal SourceMonitor::FetchFeedJob, enqueued[:job]
          assert_equal source.id, enqueued[:args].first
          assert_equal false, enqueued[:args].last["force"]

          source.reload
          assert_equal 1, source.fetch_retry_attempt
          assert_in_delta 2.minutes.from_now, source.next_fetch_at, 1.second
        end

        clear_enqueued_jobs
      end

      test "opens circuit after exceeding retry attempts" do
        source = create_source
        error = SourceMonitor::Fetching::TimeoutError.new("timeout")
        stub_fetcher = build_timeout_failure_fetcher(error)

        travel_to Time.zone.parse("2025-10-11 10:00:00 UTC") do
          SourceMonitor::Realtime.stub :broadcast_source, nil do
            3.times do |attempt|
              clear_enqueued_jobs

              if attempt < 2
                assert_enqueued_jobs 1 do
                  FetchRunner.new(source:, fetcher_class: stub_fetcher).run
                end
              else
                assert_enqueued_jobs 0 do
                  FetchRunner.new(source:, fetcher_class: stub_fetcher).run
                end
              end

              source.reload
            end
          end

          source.reload
          assert source.fetch_circuit_open?
          assert source.fetch_circuit_until > Time.current
          assert_equal 0, source.fetch_retry_attempt
        end

        clear_enqueued_jobs
      end

      test "success resets retry counters and closes circuit" do
        source = create_source

        # First failure triggers retry attempt
        error = SourceMonitor::Fetching::TimeoutError.new("timeout")
        failure_fetcher = build_timeout_failure_fetcher(error)

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          travel_to Time.zone.parse("2025-10-11 11:00:00 UTC") do
            assert_enqueued_jobs 1 do
              FetchRunner.new(source:, fetcher_class: failure_fetcher).run
            end
          end
        end

        clear_enqueued_jobs
        source.reload
        assert_equal 1, source.fetch_retry_attempt

        success_fetcher = build_success_fetcher

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          travel_to Time.zone.parse("2025-10-11 11:05:00 UTC") do
            assert_enqueued_jobs 0 do
              FetchRunner.new(source:, fetcher_class: success_fetcher).run
            end
          end
        end

        source.reload
        assert_equal 0, source.fetch_retry_attempt
        refute source.fetch_circuit_open?
        assert_nil source.fetch_circuit_until
      end

      test "DB update failure in update_source_state! propagates" do
        source = create_source

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) do
            SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)
          end
        end

        # Stub update! to raise on the mark_complete! call (second update! call)
        call_count = 0
        original_update = source.method(:update!)
        source.define_singleton_method(:update!) do |attrs|
          call_count += 1
          raise ActiveRecord::ConnectionNotEstablished, "connection lost" if call_count >= 2
          original_update.call(attrs)
        end

        assert_raises(ActiveRecord::ConnectionNotEstablished) do
          FetchRunner.new(source:, fetcher_class: stub_fetcher).run
        end
      end

      test "broadcast failure is swallowed and source still updates" do
        source = create_source

        stub_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) do
            SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)
          end
        end

        SourceMonitor::Realtime.stub :broadcast_source, ->(_) { raise StandardError, "broadcast boom" } do
          FetchRunner.new(source:, fetcher_class: stub_fetcher).run
        end

        source.reload
        assert_equal "idle", source.fetch_status
        assert_not_nil source.last_fetch_started_at
      end

      test "ensure block resets fetch_status from fetching on unexpected error" do
        source = create_source

        # Fetcher that raises after mark_fetching! has already run
        failing_fetcher = Class.new do
          define_method(:initialize) { |**_kwargs| }
          define_method(:call) { raise StandardError, "unexpected" }
        end

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          assert_raises(StandardError) do
            FetchRunner.new(source:, fetcher_class: failing_fetcher).run
          end
        end

        # The ensure block should have caught the "fetching" status and reset to "failed"
        assert_equal "failed", source.reload.fetch_status
      end

      test "force run bypasses open circuit" do
        source = create_source
        source.update!(
          fetch_circuit_opened_at: Time.zone.parse("2025-10-11 08:50:00 UTC"),
          fetch_circuit_until: Time.zone.parse("2025-10-11 12:00:00 UTC")
        )

        stub_fetcher = build_success_fetcher

        SourceMonitor::Realtime.stub :broadcast_source, nil do
          assert_enqueued_jobs 0 do
            FetchRunner.new(source:, fetcher_class: stub_fetcher, force: true).run
          end
        end

        source.reload
        refute source.fetch_circuit_open?
        assert_nil source.fetch_circuit_until
        assert_equal 0, source.fetch_retry_attempt
      end

      private

      def create_source(scraping_enabled: false, auto_scrape: false)
        create_source!(
          scraping_enabled: scraping_enabled,
          auto_scrape: auto_scrape
        )
      end

      def empty_processing_result
        SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
          created: 0,
          updated: 0,
          failed: 0,
          items: [],
          errors: [],
          created_items: [],
          updated_items: []
        )
      end

      def apply_decision!(source, decision, now)
        return unless decision

        if decision.open_circuit?
          source.update!(
            fetch_retry_attempt: 0,
            fetch_circuit_opened_at: now,
            fetch_circuit_until: decision.circuit_until,
            next_fetch_at: decision.circuit_until,
            backoff_until: decision.circuit_until
          )
        elsif decision.retry?
          retry_at = now + decision.wait
          source.update!(
            fetch_retry_attempt: decision.next_attempt,
            fetch_circuit_opened_at: nil,
            fetch_circuit_until: nil,
            next_fetch_at: retry_at,
            backoff_until: retry_at
          )
        end
      end

      def clear_retry_state!(source)
        source.update!(
          fetch_retry_attempt: 0,
          fetch_circuit_opened_at: nil,
          fetch_circuit_until: nil
        )
      end

      def build_timeout_failure_fetcher(error)
        context = self

        Class.new do
          define_method(:initialize) do |source:, **|
            @source = source
          end

          define_method(:call) do
            now = Time.current
            decision = SourceMonitor::Fetching::RetryPolicy.new(source: @source, error: error, now: now).decision
            context.send(:apply_decision!, @source, decision, now)
            SourceMonitor::Fetching::FeedFetcher::Result.new(
              status: :failed,
              error: error,
              retry_decision: decision,
              item_processing: context.send(:empty_processing_result)
            )
          end
        end
      end

      def build_success_fetcher
        context = self

        Class.new do
          define_method(:initialize) do |source:, **|
            @source = source
          end

          define_method(:call) do
            context.send(:clear_retry_state!, @source)
            SourceMonitor::Fetching::FeedFetcher::Result.new(
              status: :fetched,
              item_processing: context.send(:empty_processing_result)
            )
          end
        end
      end

      class DummyFetcher
        def initialize(*); end

        def call
          SourceMonitor::Fetching::FeedFetcher::Result.new(status: :not_modified)
        end
      end

      class HandlerSpy
        attr_reader :calls

        def initialize
          @calls = []
        end

        def call(source:, result:)
          calls << { source:, result: }
        end
      end
    end
  end
end
