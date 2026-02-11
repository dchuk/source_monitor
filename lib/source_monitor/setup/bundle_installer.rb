# frozen_string_literal: true

module SourceMonitor
  module Setup
    class BundleInstaller
      def initialize(shell: ShellRunner.new)
        @shell = shell
      end

      def install
        shell.run("bundle", "install")
      end

      private

      attr_reader :shell
    end
  end
end
