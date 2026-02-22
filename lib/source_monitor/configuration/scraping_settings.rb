# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ScrapingSettings
      attr_accessor :max_in_flight_per_source, :max_bulk_batch_size, :min_scrape_interval

      DEFAULT_MAX_IN_FLIGHT = nil
      DEFAULT_MAX_BULK_BATCH_SIZE = 100
      DEFAULT_MIN_SCRAPE_INTERVAL = 1.0

      def initialize
        reset!
      end

      def reset!
        @max_in_flight_per_source = DEFAULT_MAX_IN_FLIGHT
        @max_bulk_batch_size = DEFAULT_MAX_BULK_BATCH_SIZE
        @min_scrape_interval = DEFAULT_MIN_SCRAPE_INTERVAL
      end

      def max_in_flight_per_source=(value)
        @max_in_flight_per_source = normalize_numeric(value)
      end

      def max_bulk_batch_size=(value)
        @max_bulk_batch_size = normalize_numeric(value)
      end

      def min_scrape_interval=(value)
        @min_scrape_interval = normalize_numeric_float(value)
      end

      private

      def normalize_numeric(value)
        return nil if value.nil?
        return nil if value == ""

        integer = value.respond_to?(:to_i) ? value.to_i : value
        integer.positive? ? integer : nil
      end

      def normalize_numeric_float(value)
        return nil if value.nil?
        return nil if value == ""

        float = value.respond_to?(:to_f) ? value.to_f : value
        float.positive? ? float : nil
      end
    end
  end
end
