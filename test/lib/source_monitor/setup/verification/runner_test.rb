# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class RunnerTest < ActiveSupport::TestCase
        test "aggregates verifier results" do
          verifier = -> { Result.new(key: :demo, name: "Demo", status: :ok, details: "Fine") }
          summary = Runner.new(verifiers: [ verifier ]).call

          assert summary.ok?
          assert_equal :ok, summary.overall_status
          assert_equal 1, summary.results.size
        end

        test "uses default verifiers" do
          queue_result = Result.new(key: :solid_queue, name: "Solid Queue", status: :ok, details: "ok")
          action_result = Result.new(key: :action_cable, name: "Action Cable", status: :ok, details: "ok")

          verifier_double = Class.new do
            attr_reader :calls

            define_method(:initialize) do |result|
              @result = result
              @calls = 0
            end

            define_method(:call) do
              @calls += 1
              @result
            end
          end

          queue_double = verifier_double.new(queue_result)
          action_double = verifier_double.new(action_result)

          SolidQueueVerifier.stub(:new, ->(*) { queue_double }) do
            ActionCableVerifier.stub(:new, ->(*) { action_double }) do
              runner = Runner.new
              summary = runner.call
              assert_equal 2, summary.results.size
              assert summary.ok?
            end
          end

          assert_equal 1, queue_double.calls
          assert_equal 1, action_double.calls
        end
      end
    end
  end
end
