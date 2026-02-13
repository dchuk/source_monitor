# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class ProcfilePatcherTest < ActiveSupport::TestCase
      test "creates Procfile.dev when missing" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "Procfile.dev")

          patcher = ProcfilePatcher.new(path: path)
          assert patcher.patch

          content = File.read(path)
          assert_includes content, "web: bin/rails server -p 3000"
          assert_includes content, "jobs: bundle exec rake solid_queue:start"
        end
      end

      test "appends jobs entry to existing Procfile.dev" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "Procfile.dev")
          File.write(path, "web: bin/rails server -p 3000\n")

          patcher = ProcfilePatcher.new(path: path)
          assert patcher.patch

          content = File.read(path)
          assert_includes content, "jobs: bundle exec rake solid_queue:start"
        end
      end

      test "skips when jobs entry already exists" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "Procfile.dev")
          File.write(path, "web: bin/rails server -p 3000\njobs: bundle exec rake solid_queue:start\n")

          patcher = ProcfilePatcher.new(path: path)
          refute patcher.patch
        end
      end
    end
  end
end
