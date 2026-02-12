# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class SolidQueueVerifierTest < ActiveSupport::TestCase
        FakeRelation = Struct.new(:records, :table_name) do
          def where(_, _)
            self
          end

          def exists?
            records.any?
          end
        end

        class FakeConnection
          def initialize(tables: [])
            @tables = tables
          end

          def table_exists?(name)
            @tables.include?(name)
          end
        end

        test "returns ok when heartbeats are present" do
          relation = FakeRelation.new([ 1 ], "solid_queue_processes")
          connection = FakeConnection.new(tables: [ "solid_queue_processes" ])

          result = SolidQueueVerifier.new(process_relation: relation, connection: connection, clock: -> { Time.current }).call

          assert_equal :ok, result.status
        end

        test "warns when no recent workers" do
          relation = FakeRelation.new([], "solid_queue_processes")
          connection = FakeConnection.new(tables: [ "solid_queue_processes" ])

          result = SolidQueueVerifier.new(process_relation: relation, connection: connection, clock: -> { Time.current }).call

          assert_equal :warning, result.status
          assert_match(/No Solid Queue workers/, result.details)
          assert_match(/Procfile\.dev/, result.remediation)
        end

        test "errors when tables missing" do
          relation = FakeRelation.new([], "solid_queue_processes")
          connection = FakeConnection.new(tables: [])

          result = SolidQueueVerifier.new(process_relation: relation, connection: connection).call

          assert_equal :error, result.status
          assert_match(/tables are missing/i, result.details)
        end

        test "errors when solid queue gem missing" do
          result = SolidQueueVerifier.new(process_relation: nil, connection: nil).call
          assert_equal :error, result.status
          assert_match(/gem is not available/i, result.details)
        end

        test "rescues unexpected failures and reports remediation" do
          relation = Class.new do
            def table_name = "solid_queue_processes"
            def where(*) = raise "boom"
          end.new

          connection = FakeConnection.new(tables: [ "solid_queue_processes" ])

          result = SolidQueueVerifier.new(process_relation: relation, connection: connection, clock: -> { Time.current }).call

          assert_equal :error, result.status
          assert_match(/verification failed/i, result.details)
          assert_match(/Verify Solid Queue migrations/, result.remediation)
        end
      end
    end
  end
end
