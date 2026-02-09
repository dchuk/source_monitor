# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class ActionCableVerifier
        def initialize(config: SourceMonitor.config.realtime, cable_config: default_cable_config, connection: default_connection)
          @config = config
          @cable_config = cable_config
          @connection = connection
        end

        def call
          case adapter
          when :solid_cable
            verify_solid_cable
          when :redis
            verify_redis
          else
            warning_result("Realtime adapter #{adapter.inspect} is not recognized", "Set config.realtime.adapter to :solid_cable or :redis in the initializer")
          end
        rescue StandardError => e
          error_result("Action Cable verification failed: #{e.message}", "Double-check Action Cable configuration and credentials")
        end

        private

        attr_reader :config, :cable_config, :connection

        def adapter
          config.adapter
        end

        def default_cable_config
          ActionCable.server.config.cable
        rescue StandardError
          {}
        end

        def default_connection
          ActiveRecord::Base.connection
        rescue StandardError
          nil
        end

        def verify_solid_cable
          unless defined?(SolidCable)
            return error_result("Solid Cable gem is not loaded", "Add `solid_cable` to your Gemfile or switch to the Redis adapter")
          end

          unless connection&.table_exists?("solid_cable_messages")
            return error_result("Solid Cable tables are missing", "Run `rails solid_cable:install` or copy the engine migration that creates solid_cable_messages")
          end

          ok_result("Solid Cable tables detected and the gem is loaded")
        end

        def verify_redis
          url = config.redis_url.presence || cable_config[:url]
          if url.blank?
            return error_result("Redis adapter configured without a URL", "Set config.realtime.redis_url or supply :url in your cable.yml")
          end

          ok_result("Redis Action Cable configuration detected (#{url})")
        end

        def ok_result(details)
          Result.new(key: :action_cable, name: "Action Cable", status: :ok, details: details)
        end

        def warning_result(details, remediation)
          Result.new(key: :action_cable, name: "Action Cable", status: :warning, details: details, remediation: remediation)
        end

        def error_result(details, remediation)
          Result.new(key: :action_cable, name: "Action Cable", status: :error, details: details, remediation: remediation)
        end
      end
    end
  end
end
