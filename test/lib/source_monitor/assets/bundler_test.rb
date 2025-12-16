require "test_helper"

module SourceMonitor
  module Assets
    class BundlerTest < ActiveSupport::TestCase
      BUILD_ROOT = SourceMonitor::Engine.root.join("app/assets/builds/source_monitor")

      setup do
        FileUtils.mkdir_p(BUILD_ROOT)
        @css_path = BUILD_ROOT.join("application.css")
        @js_path = BUILD_ROOT.join("application.js")
        # Preserve original files if they exist (for gem build)
        @original_css = File.read(@css_path) if File.exist?(@css_path)
        @original_js = File.read(@js_path) if File.exist?(@js_path)
      end

      teardown do
        # Restore original files if they existed, otherwise remove test files
        if @original_css
          File.write(@css_path, @original_css)
        else
          FileUtils.rm_f(@css_path)
        end
        if @original_js
          File.write(@js_path, @original_js)
        else
          FileUtils.rm_f(@js_path)
        end
      end

      test "build! runs npm build in the engine root" do
        captured = {}

        SourceMonitor::Assets::Bundler.stub(:run_script!, ->(script, watch: false) {
          captured[:script] = script
          captured[:watch] = watch
        }) do
          SourceMonitor::Assets::Bundler.build!
        end

        assert_equal "build", captured[:script]
        assert_not captured[:watch]
      end

      test "build_css! delegates to npm build:css" do
        captured = nil

        SourceMonitor::Assets::Bundler.stub(:run_script!, ->(script, watch: false) { captured = [ script, watch ] }) do
          SourceMonitor::Assets::Bundler.build_css!
        end

        assert_equal [ "build:css", false ], captured
      end

      test "build_js! delegates to npm build:js" do
        captured = nil

        SourceMonitor::Assets::Bundler.stub(:run_script!, ->(script, watch: false) { captured = [ script, watch ] }) do
          SourceMonitor::Assets::Bundler.build_js!
        end

        assert_equal [ "build:js", false ], captured
      end

      test "verify! raises when a build artifact is missing" do
        FileUtils.rm_f(@css_path)
        File.write(@js_path, "// built js")

        error = assert_raises SourceMonitor::Assets::Bundler::MissingBuildError do
          SourceMonitor::Assets::Bundler.verify!
        end

        assert_match "application.css", error.message
      end

      test "verify! passes when both CSS and JS artifacts exist" do
        File.write(@css_path, "/* built css */")
        File.write(@js_path, "// built js")

        assert SourceMonitor::Assets::Bundler.verify!
      end
    end
  end
end
