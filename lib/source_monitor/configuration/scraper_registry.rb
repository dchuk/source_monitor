# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module SourceMonitor
  class Configuration
    class ScraperRegistry
      include Enumerable

      def initialize
        @adapters = {}
      end

      def register(name, adapter)
        key = normalize_name(name)
        @adapters[key] = normalize_adapter(adapter)
      end

      def unregister(name)
        @adapters.delete(normalize_name(name))
      end

      def adapter_for(name)
        adapter = @adapters[normalize_name(name)]
        adapter if adapter
      end

      def each(&block)
        @adapters.each(&block)
      end

      private

      def normalize_name(name)
        value = name.to_s
        raise ArgumentError, "Invalid scraper adapter name #{name.inspect}" unless value.match?(/\A[a-z0-9_]+\z/i)

        value.downcase
      end

      def normalize_adapter(adapter)
        constant = resolve_adapter(adapter)

        if defined?(SourceMonitor::Scrapers::Base) && !(constant <= SourceMonitor::Scrapers::Base)
          raise ArgumentError, "Scraper adapters must inherit from SourceMonitor::Scrapers::Base"
        end

        constant
      end

      def resolve_adapter(adapter)
        return adapter if adapter.is_a?(Class)

        if adapter.respond_to?(:to_s)
          constant_name = adapter.to_s
          begin
            return constant_name.constantize
          rescue NameError
            raise ArgumentError, "Unknown scraper adapter constant #{constant_name.inspect}"
          end
        end

        raise ArgumentError, "Invalid scraper adapter #{adapter.inspect}"
      end
    end
  end
end
