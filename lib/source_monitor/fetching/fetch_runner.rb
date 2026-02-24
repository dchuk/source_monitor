# frozen_string_literal: true

require "source_monitor/fetching/advisory_lock"
require "source_monitor/fetching/completion/retention_handler"
require "source_monitor/fetching/completion/follow_up_handler"
require "source_monitor/fetching/completion/event_publisher"

module SourceMonitor
  module Fetching
    # Coordinates execution of FeedFetcher while ensuring we do not run more than
    # one fetch per-source concurrently. The runner also centralizes the logic
    # for queuing follow-up scraping jobs so both background jobs and manual UI
    # entry points share the same behavior.
    class FetchRunner
      LOCK_NAMESPACE = 1_746_219

      class ConcurrencyError < StandardError; end

      attr_reader :source, :fetcher_class, :force, :lock, :retention_handler, :follow_up_handler, :event_publisher

      def initialize(source:, fetcher_class: SourceMonitor::Fetching::FeedFetcher, scrape_job_class: SourceMonitor::ScrapeItemJob, scrape_enqueuer_class: SourceMonitor::Scraping::Enqueuer, retention_pruner_class: SourceMonitor::Items::RetentionPruner, lock_factory: SourceMonitor::Fetching::AdvisoryLock, retention_handler: nil, follow_up_handler: nil, event_publisher: nil, force: false)
        @source = source
        @fetcher_class = fetcher_class
        @force = force
        @lock = lock_factory.new(
          namespace: LOCK_NAMESPACE,
          key: source.id,
          connection_pool: ActiveRecord::Base.connection_pool
        )
        @retention_handler = retention_handler || SourceMonitor::Fetching::Completion::RetentionHandler.new(pruner: retention_pruner_class)
        @follow_up_handler = follow_up_handler || SourceMonitor::Fetching::Completion::FollowUpHandler.new(enqueuer_class: scrape_enqueuer_class, job_class: scrape_job_class)
        @event_publisher = event_publisher || SourceMonitor::Fetching::Completion::EventPublisher.new
        @retry_scheduled = false
      end

      def self.run(source:, **options)
        new(source:, **options).run
      end

      def self.enqueue(source_or_id, force: false)
        source = resolve_source(source_or_id)
        return unless source

        # Don't broadcast here - controller handles immediate UI update
        source.update!(fetch_status: "queued")
        SourceMonitor::FetchFeedJob.perform_later(source.id, force: force)
      end

      def run
        return skip_due_to_circuit if circuit_blocked?

        @retry_scheduled = false
        result = nil

        lock.with_lock do
          mark_fetching!
          result = fetcher_class.new(source: source).call
          retention_handler.call(source:, result:)
          follow_up_handler.call(source:, result:)
          schedule_retry_if_needed(result)
          mark_complete!(result)
        end

        event_publisher.call(source:, result:)
        result
      rescue SourceMonitor::Fetching::AdvisoryLock::NotAcquiredError => error
        raise ConcurrencyError, error.message
      rescue StandardError => error
        mark_failed!(error)
        event_publisher.call(source:, result: nil)
        raise
      ensure
        begin
          source.reload
          source.update!(fetch_status: "failed") if source.fetch_status == "fetching"
        rescue StandardError # :nocov:
          nil
        end
      end

      private

      def self.resolve_source(source_or_id)
        return source_or_id if source_or_id.is_a?(SourceMonitor::Source)

        SourceMonitor::Source.find_by(id: source_or_id)
      end
      private_class_method :resolve_source

      def self.update_source_state!(source, attrs)
        source.update!(attrs)
        begin
          SourceMonitor::Realtime.broadcast_source(source)
        rescue StandardError => error
          Rails.logger.error(
            "[SourceMonitor] Failed to broadcast source #{source.id}: #{error.class}: #{error.message}"
          ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        end
      end
      private_class_method :update_source_state!

      def circuit_blocked?
        !force && source.fetch_circuit_open?
      end

      def skip_due_to_circuit
        update_source_state(fetch_status: "failed")
        event_publisher.call(source:, result: nil)
        nil
      end

      def mark_fetching!
        update_source_state(fetch_status: "fetching", last_fetch_started_at: Time.current)
      end

      def mark_complete!(result)
        status = result&.status
        new_status =
          if @retry_scheduled
            "queued"
          else
            status == :failed ? "failed" : "idle"
          end
        update_source_state(fetch_status: new_status)
      end

      def mark_failed!(_error)
        @retry_scheduled = false
        update_source_state(fetch_status: "failed")
      end

      def update_source_state(attrs)
        self.class.send(:update_source_state!, source, attrs)
      end

      def schedule_retry_if_needed(result)
        decision = result&.retry_decision
        return unless decision&.retry?

        wait = decision.wait || 0
        queue = SourceMonitor::FetchFeedJob.set(wait: wait)
        queue.perform_later(source.id, force: false)
        @retry_scheduled = true
      rescue StandardError => error
        Rails.logger.error(
          "[SourceMonitor] Failed to enqueue retry for source #{source.id}: #{error.class}: #{error.message}"
        ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      end
    end
  end
end
