# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module Completion
      # Applies item retention after a fetch completes.
      class RetentionHandler
        Result = Struct.new(:status, :removed_total, :error, keyword_init: true) do
          def success?
            status != :failed
          end
        end

        def initialize(pruner: SourceMonitor::Items::RetentionPruner)
          @pruner = pruner
        end

        def call(source:, result:) # rubocop:disable Lint/UnusedMethodArgument
          pruner_result = pruner.call(
            source: source,
            strategy: SourceMonitor.config.retention.strategy
          )
          removed = pruner_result.respond_to?(:removed_total) ? pruner_result.removed_total : 0
          Result.new(status: :applied, removed_total: removed)
        rescue StandardError => error
          Rails.logger.error(
            "[SourceMonitor::Fetching::Completion::RetentionHandler] Retention pruning failed for source #{source.id}: #{error.class} - #{error.message}"
          )
          Result.new(status: :failed, removed_total: 0, error: error)
        end

        private

        attr_reader :pruner
      end
    end
  end
end
