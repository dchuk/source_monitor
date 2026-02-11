# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ValidationDefinition
      attr_reader :handler, :options

      def initialize(handler, options)
        @handler = handler
        @options = options
      end

      def signature
        handler_key =
          case handler
          when Symbol
            [ :symbol, handler ]
          when String
            [ :symbol, handler.to_sym ]
          else
            [ :callable, handler.object_id ]
          end

        [ handler_key, options ]
      end

      def symbol?
        handler.is_a?(Symbol) || handler.is_a?(String)
      end
    end
  end
end
