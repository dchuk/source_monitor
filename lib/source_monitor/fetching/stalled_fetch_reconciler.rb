# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module SourceMonitor
  module Fetching
    class StalledFetchReconciler
      Result = Struct.new(:recovered_source_ids, :jobs_removed, :executed_at, keyword_init: true)

      FAILURE_MESSAGE = "Fetch job stalled; resetting state and retrying"

      def self.call(now: Time.current, stale_after: nil)
        new(now:, stale_after: stale_after || default_stale_after).call
      end

      def initialize(now:, stale_after:)
        @now = now
        @stale_after = stale_after
      end

      def call
        recovered_ids = []
        removed_job_ids = []
        jobs_supported = jobs_supported?

        stale_sources.find_each do |source|
          recovery = recover_source(source, jobs_supported:)
          next if recovery.nil?

          recovered_ids << recovery[:source_id] if recovery[:source_id]
          removed_job_ids.concat(Array(recovery[:removed_job_ids]))
        end

        Result.new(
          recovered_source_ids: recovered_ids.uniq,
          jobs_removed: removed_job_ids.uniq,
          executed_at: now
        )
      end

      private

      attr_reader :now, :stale_after

      def self.default_stale_after
        SourceMonitor.config.fetching.stale_timeout_minutes.minutes
      rescue NoMethodError
        10.minutes
      end

      def stale_sources
        cutoff = now - stale_after
        SourceMonitor::Source.
          where(fetch_status: "fetching").
          where.not(last_fetch_started_at: nil).
          where(SourceMonitor::Source.arel_table[:last_fetch_started_at].lteq(cutoff))
      end

      def recover_source(source, jobs_supported:)
        removed_job_ids = []

        source.with_lock do
          source.reload
          return nil unless stale?(source)

          removed_job_ids = jobs_supported ? discard_jobs_for(source) : []
          mark_source_failed!(source)
          enqueue_recovery(source)

          { source_id: source.id, removed_job_ids: removed_job_ids }
        end
      rescue StandardError => error
        log_recovery_failure(source, error)
        nil
      end

      def stale?(source)
        source.fetch_status == "fetching" &&
          source.last_fetch_started_at.present? &&
          source.last_fetch_started_at <= now - stale_after
      end

      def discard_jobs_for(source)
        return [] unless jobs_supported?

        matching_jobs = jobs_for(source)
        removed = []

        matching_jobs.find_each do |job|
          removed << job.id
          if job.failed_execution.present?
            job.failed_execution.discard
          else
            job.destroy!
          end
        end

        removed
      end

      def jobs_for(source)
        return ::SolidQueue::Job.none unless jobs_supported?

        queue_name = SourceMonitor.queue_name(:fetch)
        ::SolidQueue::Job.
          where(queue_name: queue_name).
          where("arguments::jsonb -> 'arguments' ->> 0 = ?", source.id.to_s)
      end

      def mark_source_failed!(source)
        failure_attrs = {
          fetch_status: "failed",
          last_error: FAILURE_MESSAGE,
          last_error_at: now,
          failure_count: source.failure_count.to_i + 1,
          next_fetch_at: now,
          updated_at: now
        }

        source.update!(failure_attrs)
        SourceMonitor::Realtime.broadcast_source(source) if SourceMonitor::Realtime.respond_to?(:broadcast_source)
      end

      def enqueue_recovery(source)
        SourceMonitor::Fetching::FetchRunner.enqueue(source, force: true)
      end

      def log_recovery_failure(source, error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.error(
          "[SourceMonitor::Fetching::StalledFetchReconciler] Failed to recover source #{source&.id}: #{error.class}: #{error.message}"
        )
      end

      def jobs_supported?
        defined?(::SolidQueue::Job) &&
          ::SolidQueue::Job.table_exists?
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        false
      end
    end
  end
end
