# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class ForceFetchLockTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup { clear_enqueued_jobs }

      test "enqueue with force: true returns :already_fetching when source is fetching" do
        source = create_source!(fetch_status: "fetching")

        result = SourceMonitor::FetchFeedJob.stub :perform_later, nil do
          FetchRunner.enqueue(source.id, force: true)
        end

        assert_equal :already_fetching, result
        assert_equal "fetching", source.reload.fetch_status
      end

      test "enqueue with force: true enqueues normally when source is idle" do
        source = create_source!(fetch_status: "idle")

        assert_enqueued_with(job: SourceMonitor::FetchFeedJob, args: [ source.id, { force: true } ]) do
          FetchRunner.enqueue(source.id, force: true)
        end

        assert_equal "queued", source.reload.fetch_status
      end

      test "enqueue with force: true enqueues normally when source is failed" do
        source = create_source!(fetch_status: "failed")

        assert_enqueued_with(job: SourceMonitor::FetchFeedJob, args: [ source.id, { force: true } ]) do
          FetchRunner.enqueue(source.id, force: true)
        end

        assert_equal "queued", source.reload.fetch_status
      end

      test "enqueue with force: false always enqueues regardless of fetching status" do
        source = create_source!(fetch_status: "fetching")

        assert_enqueued_with(job: SourceMonitor::FetchFeedJob, args: [ source.id, { force: false } ]) do
          FetchRunner.enqueue(source.id, force: false)
        end

        assert_equal "queued", source.reload.fetch_status
      end

      test "enqueue with force: false enqueues when source is idle" do
        source = create_source!(fetch_status: "idle")

        assert_enqueued_with(job: SourceMonitor::FetchFeedJob, args: [ source.id, { force: false } ]) do
          FetchRunner.enqueue(source.id, force: false)
        end

        assert_equal "queued", source.reload.fetch_status
      end

      test "enqueue with force: true does not create a job when source is fetching" do
        source = create_source!(fetch_status: "fetching")

        assert_no_enqueued_jobs only: SourceMonitor::FetchFeedJob do
          FetchRunner.enqueue(source.id, force: true)
        end
      end
    end
  end
end
