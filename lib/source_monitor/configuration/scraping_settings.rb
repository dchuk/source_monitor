# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ScrapingSettings
      attr_accessor :max_in_flight_per_source, :max_bulk_batch_size

      DEFAULT_MAX_IN_FLIGHT = 25
      DEFAULT_MAX_BULK_BATCH_SIZE = 100

      def initialize
        reset!
      end

      def reset!
        @max_in_flight_per_source = DEFAULT_MAX_IN_FLIGHT
        @max_bulk_batch_size = DEFAULT_MAX_BULK_BATCH_SIZE
      end

      def max_in_flight_per_source=(value)
        @max_in_flight_per_source = normalize_numeric(value)
      end

      def max_bulk_batch_size=(value)
        @max_bulk_batch_size = normalize_numeric(value)
      end

      private

      def normalize_numeric(value)
        return nil if value.nil?
        return nil if value == ""

        integer = value.respond_to?(:to_i) ? value.to_i : value
        integer.positive? ? integer : nil
      end
    end
  end
end
