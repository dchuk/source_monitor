# frozen_string_literal: true

module SourceMonitor
  class ItemCleanupJob < ApplicationJob
    DEFAULT_BATCH_SIZE = 100

    source_monitor_queue :maintenance

    def perform(options = nil)
      options = SourceMonitor::Jobs::CleanupOptions.normalize(options)

      scope = resolve_scope(options)
      batch_size = SourceMonitor::Jobs::CleanupOptions.batch_size(options, default: DEFAULT_BATCH_SIZE)
      now = SourceMonitor::Jobs::CleanupOptions.resolve_time(options[:now])
      strategy = resolve_strategy(options)
      pruner_class = options[:retention_pruner_class] || SourceMonitor::Items::RetentionPruner

      scope.find_in_batches(batch_size:) do |batch|
        batch.each do |source|
          pruner_class.call(source:, now:, strategy:)
        end
      end
    end

    private

    def resolve_scope(options)
      relation = options[:source_scope] || SourceMonitor::Source.all
      ids = SourceMonitor::Jobs::CleanupOptions.extract_ids([ options[:source_ids], options[:source_id] ])

      if ids.any?
        relation.where(id: ids)
      else
        relation
      end
    end

    def resolve_strategy(options)
      if options.key?(:strategy)
        options[:strategy]
      elsif options.key?(:soft_delete)
        ActiveModel::Type::Boolean.new.cast(options[:soft_delete]) ? :soft_delete : :destroy
      else
        SourceMonitor.config.retention.strategy
      end
    end
  end
end
