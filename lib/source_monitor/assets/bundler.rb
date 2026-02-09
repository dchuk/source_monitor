# frozen_string_literal: true

module SourceMonitor
  module Assets
    module Bundler
      MissingBuildError = Class.new(StandardError)

      module_function

      def build!
        run_script!("build")
      end

      def build_css!
        run_script!("build:css")
      end

      def build_js!
        run_script!("build:js")
      end

      def verify!
        missing = build_artifacts.reject(&:exist?)

        if missing.any?
          relative_paths = missing.map { |path| path.relative_path_from(engine_root) }
          raise MissingBuildError,
            "SourceMonitor asset build artifacts missing: #{relative_paths.join(', ')}. Run `npm run build` in the engine root to regenerate."
        end

        true
      end

      def build_artifacts
        [
          engine_root.join("app/assets/builds/source_monitor/application.css"),
          engine_root.join("app/assets/builds/source_monitor/application.js")
        ]
      end

      def run_script!(script)
        command = [ "npm", "run", script ]
        system({ "BUNDLE_GEMFILE" => engine_root.join("Gemfile").to_s }, *command, chdir: engine_root.to_s, exception: true)
      end

      def engine_root
        SourceMonitor::Engine.root
      end
    end
  end
end
