# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class RealtimeSettings
      VALID_ADAPTERS = %i[solid_cable redis async].freeze

      attr_reader :adapter, :solid_cable
      attr_accessor :redis_url

      def initialize
        reset!
      end

      def adapter=(value)
        value = value&.to_sym
        unless VALID_ADAPTERS.include?(value)
          raise ArgumentError, "Unsupported realtime adapter #{value.inspect}"
        end

        @adapter = value
      end

      def reset!
        @solid_cable = SolidCableOptions.new
        @redis_url = nil
        self.adapter = :solid_cable
      end

      def solid_cable=(options)
        solid_cable.assign(options)
      end

      def action_cable_config
        case adapter
        when :solid_cable
          solid_cable.to_h.merge(adapter: "solid_cable")
        when :redis
          config = { adapter: "redis" }
          config[:url] = redis_url if redis_url.present?
          config
        when :async
          { adapter: "async" }
        else
          {}
        end
      end

      class SolidCableOptions
        attr_accessor :polling_interval,
          :message_retention,
          :autotrim,
          :silence_polling,
          :use_skip_locked,
          :trim_batch_size,
          :connects_to

        def initialize
          reset!
        end

        def assign(options)
          return unless options.respond_to?(:each)

          options.each do |key, value|
            setter = "#{key}="
            public_send(setter, value) if respond_to?(setter)
          end
        end

        def reset!
          @polling_interval = "0.1.seconds"
          @message_retention = "1.day"
          @autotrim = true
          @silence_polling = true
          @use_skip_locked = true
          @trim_batch_size = nil
          @connects_to = nil
        end

        def to_h
          {
            polling_interval: polling_interval,
            message_retention: message_retention,
            autotrim: autotrim,
            silence_polling: silence_polling,
            use_skip_locked: use_skip_locked,
            trim_batch_size: trim_batch_size,
            connects_to: connects_to
          }.compact
        end
      end
    end
  end
end
