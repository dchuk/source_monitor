# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class Models
      MODEL_KEYS = {
        source: :source,
        item: :item,
        fetch_log: :fetch_log,
        scrape_log: :scrape_log,
        health_check_log: :health_check_log,
        item_content: :item_content,
        log_entry: :log_entry
      }.freeze

      attr_accessor :table_name_prefix

      def initialize
        @table_name_prefix = "sourcemon_"
        @definitions = MODEL_KEYS.transform_values { ModelDefinition.new }
      end

      MODEL_KEYS.each do |method_name, key|
        define_method(method_name) { @definitions[key] }
      end

      def for(name)
        key = name.to_sym
        definition = @definitions[key]
        raise ArgumentError, "Unknown model #{name.inspect}" unless definition

        definition
      end
    end
  end
end
