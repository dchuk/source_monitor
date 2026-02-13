# frozen_string_literal: true

require "pathname"

module SourceMonitor
  module Setup
    class ProcfilePatcher
      JOBS_ENTRY = "jobs: bundle exec rake solid_queue:start"

      def initialize(path: "Procfile.dev")
        @path = Pathname.new(path)
      end

      def patch
        if path.exist?
          content = path.read
          return false if content.match?(/^jobs:/)

          path.open("a") { |f| f.puts("", JOBS_ENTRY) }
        else
          path.write("web: bin/rails server -p 3000\n#{JOBS_ENTRY}\n")
        end
        true
      end

      private

      attr_reader :path
    end
  end
end
