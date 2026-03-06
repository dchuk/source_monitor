# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class BlockedErrorTest < ActiveSupport::TestCase
      test "has CODE set to blocked" do
        assert_equal "blocked", BlockedError::CODE
      end

      test "inherits from FetchError" do
        error = BlockedError.new
        assert_kind_of FetchError, error
      end

      test "accepts blocked_by keyword" do
        error = BlockedError.new(blocked_by: "cloudflare")
        assert_equal "cloudflare", error.blocked_by
      end

      test "defaults blocked_by to unknown" do
        error = BlockedError.new
        assert_equal "unknown", error.blocked_by
      end

      test "includes blocked_by in default message" do
        error = BlockedError.new(blocked_by: "captcha")
        assert_equal "Feed blocked by captcha", error.message
      end

      test "code method returns CODE" do
        error = BlockedError.new
        assert_equal "blocked", error.code
      end

      test "accepts response keyword" do
        response = Object.new
        error = BlockedError.new(blocked_by: "cloudflare", response: response)
        assert_equal response, error.response
      end
    end

    class AuthenticationErrorTest < ActiveSupport::TestCase
      test "has CODE set to authentication" do
        assert_equal "authentication", AuthenticationError::CODE
      end

      test "inherits from FetchError" do
        error = AuthenticationError.new
        assert_kind_of FetchError, error
      end

      test "has default message" do
        error = AuthenticationError.new
        assert_equal "Authentication required", error.message
      end

      test "code method returns CODE" do
        error = AuthenticationError.new
        assert_equal "authentication", error.code
      end
    end
  end
end
