# frozen_string_literal: true

require "pathname"

module SourceMonitor
  module Setup
    class GemfileEditor
      attr_reader :path

      def initialize(path: "Gemfile")
        @path = Pathname.new(path)
      end

      def ensure_entry
        return false unless path.exist?

        contents = path.read
        return false if contents.match?(/gem\s+['"]source_monitor['"]/)

        path.open("a") do |file|
          file.write(<<~RUBY)

            gem "source_monitor"
          RUBY
        end

        true
      end
    end
  end
end
