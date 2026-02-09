# frozen_string_literal: true

require "pathname"

module SourceMonitor
  module Setup
    class InitializerPatcher
      AUTH_MARKER = "# ---- Authentication".freeze

      def initialize(path: "config/initializers/source_monitor.rb")
        @path = Pathname.new(path)
      end

      def ensure_navigation_hint(mount_path: Workflow::DEFAULT_MOUNT_PATH)
        return false unless path.exist?

        comment = "# Mount SourceMonitor at #{mount_path} so admins can find the dashboard."
        contents = path.read
        return false if contents.include?(comment)

        updated = contents.sub("# SourceMonitor engine configuration.", "# SourceMonitor engine configuration.\n#{comment}")
        path.write(updated)
        true
      end

      def ensure_devise_hooks
        return false unless path.exist?

        contents = path.read
        return false if contents.include?("config.authentication.authenticate_with :authenticate_user!")

        snippet = indent(devise_snippet)
        updated = if contents.include?(AUTH_MARKER)
          contents.sub(AUTH_MARKER, "#{AUTH_MARKER}\n#{snippet}")
        else
          contents.sub(/SourceMonitor.configure do \|config\|/m, "\\0\n#{snippet}")
        end

        path.write(updated)
        true
      end

      private

      attr_reader :path

      def indent(text)
        text.lines.map { |line| line.strip.empty? ? "\n" : "  #{line}" }.join
      end

      def devise_snippet
        <<~RUBY
          config.authentication.authenticate_with :authenticate_user!
          config.authentication.authorize_with ->(controller) { controller.current_user&.respond_to?(:admin?) ? controller.current_user.admin? : true }
          config.authentication.current_user_method = :current_user
          config.authentication.user_signed_in_method = :user_signed_in?
        RUBY
      end
    end
  end
end
