# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class QueueConfigPatcherTest < ActiveSupport::TestCase
      test "adds recurring_schedule to existing dispatcher" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "queue.yml")
          File.write(path, YAML.dump(
            "production" => {
              "dispatchers" => [ { "polling_interval" => 1, "batch_size" => 500 } ]
            }
          ))

          patcher = QueueConfigPatcher.new(path: path)
          assert patcher.patch

          parsed = YAML.safe_load(File.read(path))
          dispatcher = parsed["production"]["dispatchers"].first
          assert_equal "config/recurring.yml", dispatcher["recurring_schedule"]
        end
      end

      test "skips when recurring_schedule already present" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "queue.yml")
          File.write(path, YAML.dump(
            "production" => {
              "dispatchers" => [ { "polling_interval" => 1, "recurring_schedule" => "config/recurring.yml" } ]
            }
          ))

          patcher = QueueConfigPatcher.new(path: path)
          refute patcher.patch
        end
      end

      test "returns false when file does not exist" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "nonexistent.yml")

          patcher = QueueConfigPatcher.new(path: path)
          refute patcher.patch
        end
      end

      test "creates dispatchers section when none exists" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "queue.yml")
          File.write(path, YAML.dump("production" => { "workers" => [ { "queues" => [ "*" ] } ] }))

          patcher = QueueConfigPatcher.new(path: path)
          assert patcher.patch

          parsed = YAML.safe_load(File.read(path))
          assert parsed.key?("dispatchers")
          assert_equal "config/recurring.yml", parsed["dispatchers"].first["recurring_schedule"]
        end
      end
    end
  end
end
