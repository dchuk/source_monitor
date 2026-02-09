# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class InitializerPatcherTest < ActiveSupport::TestCase
      SETUP_INITIALIZER = File.read(File.expand_path("../../../../lib/generators/source_monitor/install/templates/source_monitor.rb.tt", __dir__))

      test "adds navigation hint with mount path" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "source_monitor.rb")
          File.write(path, SETUP_INITIALIZER)

          patcher = InitializerPatcher.new(path: path)

          assert patcher.ensure_navigation_hint(mount_path: "/admin/monitor")
          assert_includes File.read(path), "# Mount SourceMonitor at /admin/monitor"
          refute patcher.ensure_navigation_hint(mount_path: "/admin/monitor")
        end
      end

      test "appends devise hooks once" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "source_monitor.rb")
          File.write(path, SETUP_INITIALIZER)

          patcher = InitializerPatcher.new(path: path)

          assert patcher.ensure_devise_hooks
          contents = File.read(path)
          assert_includes contents, "config.authentication.authenticate_with :authenticate_user!"
          refute patcher.ensure_devise_hooks
        end
      end
    end
  end
end
