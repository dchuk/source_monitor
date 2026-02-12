# frozen_string_literal: true

require "pathname"
require "yaml"

module SourceMonitor
  module Setup
    class QueueConfigPatcher
      RECURRING_SCHEDULE_VALUE = "config/recurring.yml"

      DEFAULT_DISPATCHER = {
        "polling_interval" => 1,
        "batch_size" => 500,
        "recurring_schedule" => RECURRING_SCHEDULE_VALUE
      }.freeze

      def initialize(path: "config/queue.yml")
        @path = Pathname.new(path)
      end

      def patch
        return false unless path.exist?

        parsed = YAML.safe_load(path.read, aliases: true) || {}
        return false if has_recurring_schedule?(parsed)

        add_recurring_schedule!(parsed)
        path.write(YAML.dump(parsed))
        true
      end

      private

      attr_reader :path

      def has_recurring_schedule?(parsed)
        parsed.each_value do |value|
          next unless value.is_a?(Hash)

          dispatchers = value["dispatchers"]
          if dispatchers.is_a?(Array)
            return true if dispatchers.any? { |d| d.is_a?(Hash) && d.key?("recurring_schedule") }
          end

          return true if has_recurring_schedule?(value)
        end

        if parsed.key?("dispatchers") && parsed["dispatchers"].is_a?(Array)
          return true if parsed["dispatchers"].any? { |d| d.is_a?(Hash) && d.key?("recurring_schedule") }
        end

        false
      end

      def add_recurring_schedule!(parsed)
        found_dispatchers = false

        parsed.each_value do |value|
          next unless value.is_a?(Hash)

          if value.key?("dispatchers") && value["dispatchers"].is_a?(Array)
            value["dispatchers"].each do |dispatcher|
              next unless dispatcher.is_a?(Hash)
              dispatcher["recurring_schedule"] ||= RECURRING_SCHEDULE_VALUE
            end
            found_dispatchers = true
          end
        end

        if parsed.key?("dispatchers") && parsed["dispatchers"].is_a?(Array)
          parsed["dispatchers"].each do |dispatcher|
            next unless dispatcher.is_a?(Hash)
            dispatcher["recurring_schedule"] ||= RECURRING_SCHEDULE_VALUE
          end
          found_dispatchers = true
        end

        unless found_dispatchers
          parsed["dispatchers"] = [ DEFAULT_DISPATCHER.dup ]
        end
      end
    end
  end
end
