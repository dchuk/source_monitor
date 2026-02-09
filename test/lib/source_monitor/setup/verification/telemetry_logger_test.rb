# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    module Verification
      class TelemetryLoggerTest < ActiveSupport::TestCase
        test "writes json payload" do
          Dir.mktmpdir do |dir|
            path = File.join(dir, "log.jsonl")
            summary = Summary.new([
              Result.new(key: :demo, name: "Demo", status: :ok, details: "fine")
            ])

            TelemetryLogger.new(path: path).log(summary)

            content = File.read(path)
            assert_includes content, "\"overall_status\":\"ok\""
          end
        end

        test "defaults to rails root log path" do
          Dir.mktmpdir do |dir|
            summary = Summary.new([
              Result.new(key: :demo, name: "Demo", status: :ok, details: "fine")
            ])

            Rails.stub(:root, Pathname.new(dir)) do
              TelemetryLogger.new.log(summary)
            end

            default_path = File.join(dir, "log", "source_monitor_setup.log")
            assert File.exist?(default_path)
            assert_includes File.read(default_path), "overall_status"
          end
        end
      end
    end
  end
end
