# frozen_string_literal: true

require "pathname"

module SourceMonitor
  module Setup
    class NodeInstaller
      def initialize(root: Pathname.pwd.to_s, shell: ShellRunner.new)
        @root = Pathname.new(root)
        @shell = shell
      end

      def install_if_needed
        return false unless package_json?

        shell.run("npm", "install")
        true
      end

      private

      attr_reader :root, :shell

      def package_json?
        root.join("package.json").exist?
      end
    end
  end
end
