# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Detectors
      extend self

      def ruby_version
        Gem::Version.new(RUBY_VERSION)
      end

      def rails_version
        return unless defined?(Rails)

        Rails.gem_version
      end

      def node_version(shell: ShellRunner.new)
        output = shell.run("node", "--version")
        return if output.blank?

        Gem::Version.new(output.strip.sub(/^v/i, ""))
      rescue ArgumentError
        nil
      end

      def postgres_adapter(config: nil, fallback: nil)
        config ||= connection_db_config
        fallback ||= primary_config

        config_adapter(config) || config_adapter(fallback)
      rescue StandardError
        nil
      end

      def solid_queue_version
        spec = Gem.loaded_specs["solid_queue"]
        spec&.version
      end

      private

      def connection_db_config
        return unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection_db_config
      rescue ActiveRecord::ConnectionNotEstablished
        nil
      end

      def primary_config
        return unless defined?(Rails)

        ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
          &.first
      rescue StandardError
        nil
      end

      def config_adapter(config)
        return if config.nil?

        config.respond_to?(:adapter) ? config.adapter : config[:adapter]
      rescue StandardError
        nil
      end
    end
  end
end
