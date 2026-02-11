# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class Events
      CALLBACK_KEYS = %i[after_item_created after_item_scraped after_fetch_completed].freeze

      def initialize
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @item_processors = []
      end

      CALLBACK_KEYS.each do |key|
        define_method(key) do |handler = nil, &block|
          register_callback(key, handler, &block)
        end
      end

      def register_item_processor(processor = nil, &block)
        callable = processor || block
        validate_callable!(callable, :item_processor)
        @item_processors << callable
        callable
      end

      def callbacks_for(name)
        @callbacks[name.to_sym]&.dup || []
      end

      def item_processors
        @item_processors.dup
      end

      def reset!
        @callbacks.clear
        @item_processors.clear
      end

      private

      def register_callback(key, handler = nil, &block)
        callable = handler || block
        validate_callable!(callable, key)
        key = key.to_sym
        unless CALLBACK_KEYS.include?(key)
          raise ArgumentError, "Unknown event #{key.inspect}"
        end

        @callbacks[key] << callable
        callable
      end

      def validate_callable!(callable, name)
        unless callable.respond_to?(:call)
          raise ArgumentError, "#{name} handler must respond to #call"
        end
      end
    end
  end
end
