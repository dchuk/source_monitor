# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ModelDefinition
      attr_reader :validations

      def initialize
        @concern_definitions = []
        @validations = []
      end

      def include_concern(concern = nil, &block)
        definition = ConcernDefinition.new(concern, block)
        unless @concern_definitions.any? { |existing| existing.signature == definition.signature }
          @concern_definitions << definition
        end

        definition.return_value
      end

      def each_concern
        return enum_for(:each_concern) unless block_given?

        @concern_definitions.each do |definition|
          yield definition.signature, definition.resolve
        end
      end

      def validate(handler = nil, **options, &block)
        callable =
          if block
            block
          elsif handler.respond_to?(:call) && !handler.is_a?(Symbol) && !handler.is_a?(String)
            handler
          elsif handler.is_a?(Symbol) || handler.is_a?(String)
            handler.to_sym
          else
            raise ArgumentError, "Invalid validation handler #{handler.inspect}"
          end

        validation = ValidationDefinition.new(callable, options)
        @validations << validation
        validation
      end

      private

      class ConcernDefinition
        attr_reader :signature

        def initialize(concern, block)
          @resolver = build_resolver(concern, block)
          @signature = build_signature(concern, block)
          @return_value = determine_return_value(concern, block)
        end

        def resolve
          @resolved ||= @resolver.call
        end

        def return_value
          @return_value
        end

        private

        def build_resolver(concern, block)
          if block
            mod = Module.new(&block)
            -> { mod }
          elsif concern.is_a?(Module)
            -> { concern }
          elsif concern.respond_to?(:to_s)
            constant_name = concern.to_s
            lambda do
              constant_name.constantize
            rescue NameError => error
              raise ArgumentError, error.message
            end
          else
            raise ArgumentError, "Invalid concern #{concern.inspect}"
          end
        end

        def build_signature(concern, block)
          if block
            [ :anonymous_module, block.object_id ]
          elsif concern.is_a?(Module)
            [ :module, concern.object_id ]
          else
            [ :constant, concern.to_s ]
          end
        end

        def determine_return_value(concern, block)
          if block
            resolve
          elsif concern.is_a?(Module)
            concern
          else
            concern
          end
        end
      end
    end
  end
end
