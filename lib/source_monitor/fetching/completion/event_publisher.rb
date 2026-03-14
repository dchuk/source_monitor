# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module Completion
      # Publishes fetch completion events to the configured event dispatcher.
      class EventPublisher
        Result = Struct.new(:status, :error, keyword_init: true) do
          def success?
            status != :failed
          end
        end

        def initialize(dispatcher: SourceMonitor::Events)
          @dispatcher = dispatcher
        end

        def call(source:, result:)
          dispatcher.after_fetch_completed(source: source, result: result)
          Result.new(status: :published)
        rescue StandardError => error
          Rails.logger.error(
            "[SourceMonitor::Fetching::Completion::EventPublisher] Event dispatch failed for source #{source.id}: #{error.class} - #{error.message}"
          ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Result.new(status: :failed, error: error)
        end

        private

        attr_reader :dispatcher
      end
    end
  end
end
