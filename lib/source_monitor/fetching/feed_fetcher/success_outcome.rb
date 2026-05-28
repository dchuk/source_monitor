# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FeedFetcher
      class SuccessOutcome
        def initialize(response:, body:, feed:, item_processing:, feed_signature:, content_changed:, entries_digest:)
          @response = response
          @body = body
          @feed = feed
          @item_processing = item_processing
          @feed_signature = feed_signature
          @content_changed = content_changed
          @entries_digest = entries_digest
        end

        attr_reader :response, :body, :feed, :item_processing, :feed_signature, :content_changed, :entries_digest

        def apply(source_updater:, started_at:, instrumentation_payload:)
          duration_ms = source_updater.elapsed_ms(started_at)
          update_source(source_updater, duration_ms)
          create_fetch_log(source_updater, duration_ms, started_at)
          apply_instrumentation(instrumentation_payload)
          result
        end

        def status
          :fetched
        end

        def error
          nil
        end

        def retry_decision
          nil
        end

        def result
          Result.new(status: status, feed: feed, response: response, body: body, item_processing: item_processing, outcome: self)
        end

        private

        def update_source(source_updater, duration_ms)
          source_updater.update_source_for_success(
            response,
            duration_ms,
            feed,
            feed_signature,
            content_changed: content_changed,
            entries_digest: entries_digest
          )
        end

        def create_fetch_log(source_updater, duration_ms, started_at)
          source_updater.create_fetch_log(
            response: response,
            duration_ms: duration_ms,
            started_at: started_at,
            feed: feed,
            success: true,
            body: body,
            feed_signature: feed_signature,
            items_created: item_processing.created,
            items_updated: item_processing.updated,
            items_failed: item_processing.failed,
            item_errors: item_processing.errors
          )
        end

        def apply_instrumentation(instrumentation_payload)
          instrumentation_payload[:success] = true
          instrumentation_payload[:status] = :fetched
          instrumentation_payload[:http_status] = response.status
          instrumentation_payload[:parser] = feed.class.name if feed
          instrumentation_payload[:items_created] = item_processing.created
          instrumentation_payload[:items_updated] = item_processing.updated
          instrumentation_payload[:items_failed] = item_processing.failed
          instrumentation_payload[:retry_attempt] = 0
        end
      end
    end
  end
end
