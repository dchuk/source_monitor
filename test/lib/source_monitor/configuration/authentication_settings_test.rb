# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class AuthenticationSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = AuthenticationSettings.new
      end

      test "initializes with nil handlers" do
        assert_nil @settings.authenticate_handler
        assert_nil @settings.authorize_handler
        assert_nil @settings.current_user_method
        assert_nil @settings.user_signed_in_method
      end

      test "authenticate_with symbol" do
        @settings.authenticate_with(:authenticate_user!)

        assert_equal :symbol, @settings.authenticate_handler.type
        assert_equal :authenticate_user!, @settings.authenticate_handler.callable
      end

      test "authenticate_with string" do
        @settings.authenticate_with("authenticate_user!")

        assert_equal :symbol, @settings.authenticate_handler.type
        assert_equal :authenticate_user!, @settings.authenticate_handler.callable
      end

      test "authenticate_with callable" do
        handler = ->(controller) { controller }
        @settings.authenticate_with(handler)

        assert_equal :callable, @settings.authenticate_handler.type
      end

      test "authenticate_with block" do
        @settings.authenticate_with { |controller| controller }

        assert_equal :callable, @settings.authenticate_handler.type
      end

      test "authorize_with symbol" do
        @settings.authorize_with(:admin_only!)

        assert_equal :symbol, @settings.authorize_handler.type
      end

      test "authenticate_with raises for invalid handler" do
        assert_raises(ArgumentError) { @settings.authenticate_with(123) }
      end

      test "handler call with symbol sends message to controller" do
        called = false
        controller = Object.new
        controller.define_singleton_method(:authenticate_user!) { called = true }

        @settings.authenticate_with(:authenticate_user!)
        @settings.authenticate_handler.call(controller)

        assert called
      end

      test "handler call with zero-arity callable uses instance_exec" do
        called = false
        handler = -> { called = true }
        @settings.authenticate_with(handler)

        controller = Object.new
        @settings.authenticate_handler.call(controller)

        assert called
      end

      test "handler call with arity-1 callable passes controller" do
        received = nil
        handler = ->(c) { received = c }
        @settings.authenticate_with(handler)

        controller = Object.new
        @settings.authenticate_handler.call(controller)

        assert_equal controller, received
      end

      test "handler call with nil callable does nothing" do
        handler = AuthenticationSettings::Handler.new(:symbol, nil)
        assert_nil handler.call(Object.new)
      end

      test "reset clears all settings" do
        @settings.authenticate_with(:authenticate!)
        @settings.authorize_with(:authorize!)
        @settings.current_user_method = :current_user
        @settings.user_signed_in_method = :user_signed_in?

        @settings.reset!

        assert_nil @settings.authenticate_handler
        assert_nil @settings.authorize_handler
        assert_nil @settings.current_user_method
        assert_nil @settings.user_signed_in_method
      end
    end
  end
end
