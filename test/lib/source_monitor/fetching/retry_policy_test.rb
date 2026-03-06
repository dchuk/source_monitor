# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class RetryPolicyTest < ActiveSupport::TestCase
      setup do
        @source = create_source!(name: "Policy Test", feed_url: "https://example.com/policy.xml")
        @source.update_columns(fetch_retry_attempt: 0)
      end

      test "blocked error uses blocked policy with 1 attempt" do
        error = BlockedError.new(blocked_by: "cloudflare")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
        refute decision.open_circuit?
      end

      test "blocked error opens circuit after 1 retry" do
        @source.update_columns(fetch_retry_attempt: 1)
        error = BlockedError.new(blocked_by: "cloudflare")
        decision = RetryPolicy.new(source: @source, error: error).decision

        refute decision.retry?
        assert decision.open_circuit?
        assert_equal 4.hours.from_now.to_i, decision.circuit_until.to_i
      end

      test "authentication error uses authentication policy with 1 attempt" do
        error = AuthenticationError.new
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
        refute decision.open_circuit?
      end

      test "authentication error opens circuit after 1 retry" do
        @source.update_columns(fetch_retry_attempt: 1)
        error = AuthenticationError.new
        decision = RetryPolicy.new(source: @source, error: error).decision

        refute decision.retry?
        assert decision.open_circuit?
        assert_equal 4.hours.from_now.to_i, decision.circuit_until.to_i
      end

      test "timeout error uses timeout policy" do
        error = TimeoutError.new("timed out")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "parsing error uses parsing policy" do
        error = ParsingError.new("bad feed")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "connection error uses connection policy with 3 attempts" do
        error = ConnectionError.new("refused")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "http 429 uses http_429 policy" do
        error = HTTPError.new(status: 429)
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "http 500 uses http_5xx policy" do
        error = HTTPError.new(status: 500)
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "http 403 uses http_4xx policy" do
        error = HTTPError.new(status: 403)
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "unexpected error uses unexpected policy" do
        error = UnexpectedResponseError.new("weird")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end

      test "unknown FetchError uses fallback policy" do
        error = FetchError.new("generic")
        decision = RetryPolicy.new(source: @source, error: error).decision

        assert decision.retry?
        assert_equal 1, decision.next_attempt
      end
    end
  end
end
