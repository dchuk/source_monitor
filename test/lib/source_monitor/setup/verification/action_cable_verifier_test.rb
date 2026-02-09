# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class ActionCableVerifierTest < ActiveSupport::TestCase
        test "ok when solid cable tables exist" do
          config = OpenStruct.new(adapter: :solid_cable)
          connection = Minitest::Mock.new
          connection.expect(:table_exists?, true, [ "solid_cable_messages" ])

          existing = Object.const_defined?(:SolidCable)
          Object.const_set(:SolidCable, Module.new) unless existing

          result = ActionCableVerifier.new(config: config, connection: connection).call

          assert_equal :ok, result.status
          connection.verify
        ensure
          Object.send(:remove_const, :SolidCable) if !existing && Object.const_defined?(:SolidCable)
        end

        test "error when redis missing url" do
          config = OpenStruct.new(adapter: :redis, redis_url: nil)
          result = ActionCableVerifier.new(config: config, cable_config: {}).call

          assert_equal :error, result.status
          assert_match(/Redis adapter configured without a URL/i, result.details)
        end
      end
    end
  end
end
require "ostruct"
