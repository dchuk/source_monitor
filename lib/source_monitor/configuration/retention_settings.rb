# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class RetentionSettings
      attr_accessor :items_retention_days, :max_items

      def initialize
        @items_retention_days = nil
        @max_items = nil
        @strategy = :destroy
      end

      def strategy
        @strategy
      end

      def strategy=(value)
        normalized = normalize_strategy(value)
        @strategy = normalized unless normalized.nil?
      end

      private

      def normalize_strategy(value)
        return :destroy if value.nil?

        if value.respond_to?(:to_sym)
          candidate = value.to_sym
          valid =
            if defined?(SourceMonitor::Items::RetentionPruner::VALID_STRATEGIES)
              SourceMonitor::Items::RetentionPruner::VALID_STRATEGIES
            else
              %i[destroy soft_delete]
            end

          raise ArgumentError, "Invalid retention strategy #{value.inspect}" unless valid.include?(candidate)
          candidate
        else
          raise ArgumentError, "Invalid retention strategy #{value.inspect}"
        end
      end
    end
  end
end
