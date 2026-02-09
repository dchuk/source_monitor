# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class DetectorsTest < ActiveSupport::TestCase
      class FakeRunner
        attr_reader :commands

        def initialize(response: nil)
          @response = response
          @commands = []
        end

        def run(*command)
          @commands << command
          @response
        end
      end

      test "node_version strips leading v prefix" do
        runner = FakeRunner.new(response: "v20.1.0\n")

        version = Detectors.node_version(shell: runner)

        assert_equal Gem::Version.new("20.1.0"), version
        assert_equal [ [ "node", "--version" ] ], runner.commands
      end

      test "node_version returns nil when command missing" do
        runner = FakeRunner.new(response: nil)

        assert_nil Detectors.node_version(shell: runner)
      end

      test "postgres_adapter falls back to configuration when connection unavailable" do
        fake_config = Struct.new(:adapter).new("postgresql")

        assert_equal "postgresql", Detectors.postgres_adapter(config: fake_config)
      end

      test "solid_queue_version reads loaded specs" do
        specs = Gem.loaded_specs.merge("solid_queue" => Gem::Specification.new do |spec|
          spec.name = "solid_queue"
          spec.version = Gem::Version.new("1.0.0")
        end)

        Gem.stub(:loaded_specs, specs) do
          assert_equal Gem::Version.new("1.0.0"), Detectors.solid_queue_version
        end
      end
    end
  end
end
