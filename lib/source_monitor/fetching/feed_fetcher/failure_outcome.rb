# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FeedFetcher
      class FailureOutcome
        def initialize(error:)
          @error = error
        end

        attr_reader :error

        def apply(source_updater:, started_at:, instrumentation_payload:)
          duration_ms = source_updater.elapsed_ms(started_at)
          retry_decision = update_source(source_updater, duration_ms)
          create_fetch_log(source_updater, duration_ms, started_at)
          apply_instrumentation(instrumentation_payload, retry_decision)
          result(retry_decision)
        end

        def response
          error.response
        end

        def body
          response&.body
        end

        private

        def update_source(source_updater, duration_ms)
          source_updater.update_source_for_failure(error, duration_ms)
        end

        def create_fetch_log(source_updater, duration_ms, started_at)
          source_updater.create_fetch_log(
            response: response,
            duration_ms: duration_ms,
            started_at: started_at,
            success: false,
            error: error,
            body: body
          )
        end

        def apply_instrumentation(instrumentation_payload, retry_decision)
          instrumentation_payload[:success] = false
          instrumentation_payload[:status] = :failed
          instrumentation_payload[:error_class] = error.class.name
          instrumentation_payload[:error_message] = error.message
          instrumentation_payload[:http_status] = error.http_status if error.http_status
          instrumentation_payload[:error_code] = error.code if error.respond_to?(:code)
          instrumentation_payload[:items_created] = 0
          instrumentation_payload[:items_updated] = 0
          instrumentation_payload[:items_failed] = 0
          instrumentation_payload[:retry_attempt] = retry_decision&.next_attempt ? retry_decision.next_attempt : 0
        end

        def result(retry_decision)
          Result.new(
            status: :failed,
            response: response,
            body: body,
            error: error,
            retry_decision: retry_decision,
            item_processing: empty_item_processing
          )
        end

        def empty_item_processing
          EntryProcessingResult.new(
            created: 0,
            updated: 0,
            unchanged: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          )
        end
      end
    end
  end
end
