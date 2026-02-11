# frozen_string_literal: true

require "fileutils"
require "pathname"

module SourceMonitor
  module Setup
    module Verification
      class TelemetryLogger
        def initialize(path: nil)
          @path = Pathname.new(path || default_path)
        end

        def log(summary)
          FileUtils.mkdir_p(path.dirname)
          path.open("a") do |file|
            file.puts({ timestamp: Time.current.iso8601, payload: summary.to_h }.to_json)
          end
        end

        private

        attr_reader :path

        def default_path
          if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
            Rails.root.join("log", "source_monitor_setup.log")
          else
            Pathname.new("log/source_monitor_setup.log")
          end
        end
      end
    end
  end
end
