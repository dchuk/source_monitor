# frozen_string_literal: true

require "open3"

module SourceMonitor
  module Setup
    class ShellRunner
      def run(*command)
        stdout, status = Open3.capture2e(*command)
        status.success? ? stdout.strip : nil
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
