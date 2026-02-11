# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class AuthenticationSettings
      Handler = Struct.new(:type, :callable) do
        def call(controller)
          return unless callable

          case type
          when :symbol
            controller.public_send(callable)
          when :callable
            arity = callable.arity
            if arity.zero?
              controller.instance_exec(&callable)
            else
              callable.call(controller)
            end
          end
        end
      end

      attr_reader :authenticate_handler, :authorize_handler
      attr_accessor :current_user_method, :user_signed_in_method

      def initialize
        reset!
      end

      def authenticate_with(handler = nil, &block)
        @authenticate_handler = build_handler(handler, &block)
      end

      def authorize_with(handler = nil, &block)
        @authorize_handler = build_handler(handler, &block)
      end

      def reset!
        @authenticate_handler = nil
        @authorize_handler = nil
        @current_user_method = nil
        @user_signed_in_method = nil
      end

      private

      def build_handler(handler = nil, &block)
        handler ||= block
        return nil unless handler

        if handler.is_a?(Symbol) || handler.is_a?(String)
          Handler.new(:symbol, handler.to_sym)
        elsif handler.respond_to?(:call)
          Handler.new(:callable, handler)
        else
          raise ArgumentError, "Invalid authentication handler #{handler.inspect}"
        end
      end
    end
  end
end
