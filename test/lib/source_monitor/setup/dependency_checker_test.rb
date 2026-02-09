# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class DependencyCheckerTest < ActiveSupport::TestCase
      Dependency = SourceMonitor::Setup::DependencyChecker::Dependency
      Result = SourceMonitor::Setup::DependencyChecker::Result

      test "call returns summary with results" do
        dependencies = [
          Dependency.new(
            key: :ruby,
            name: "Ruby",
            requirement: Requirements::Version.new(">= 3.4"),
            detector: -> { Gem::Version.new("3.4.5") },
            remediation: "Upgrade Ruby"
          ),
          Dependency.new(
            key: :node,
            name: "Node",
            requirement: Requirements::Version.new(">= 18"),
            detector: -> { Gem::Version.new("16.0.0") },
            remediation: "Install Node 18"
          )
        ]

        summary = DependencyChecker.new(dependencies:).call

        assert_equal 2, summary.results.count
        assert summary.results.find { |r| r.key == :ruby }.ok?
        refute summary.results.find { |r| r.key == :node }.ok?
        assert_equal :error, summary.overall_status
      end

      test "missing detector output marks dependency missing" do
        dependency = Dependency.new(
          key: :postgres,
          name: "PostgreSQL",
          requirement: Requirements::Adapter.new("postgresql"),
          detector: -> { nil },
          remediation: "Configure PostgreSQL"
        )

        summary = DependencyChecker.new(dependencies: [ dependency ]).call
        result = summary.results.first

        assert result.missing?
        assert_equal :missing, result.status
        assert_equal :error, summary.overall_status
      end

      test "default dependencies include all required checks" do
        summary = DependencyChecker.new.call
        keys = summary.results.map(&:key)

        %i[ruby rails node postgres solid_queue].each do |key|
          assert_includes keys, key
        end
      end
    end
  end
end
