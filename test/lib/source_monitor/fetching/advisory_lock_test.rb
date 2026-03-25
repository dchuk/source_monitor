# frozen_string_literal: true

require "test_helper"
require "source_monitor/fetching/advisory_lock"

module SourceMonitor
  module Fetching
    class AdvisoryLockTest < ActiveSupport::TestCase
      LOCK_NAMESPACE = 9_812_345

      class TestError < StandardError; end

      test "yields when the advisory lock is acquired and releases afterwards" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        executed = false
        lock.with_lock do
          executed = true
        end

        assert executed, "expected block to run"
        assert lock_available?(LOCK_NAMESPACE, key), "expected lock to be released after yielding"
      end

      test "raises not acquired error when lock is already held" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        # Stub the connection pool to inject a fake connection that always
        # returns false for pg_try_advisory_lock. Class.new is used here
        # because .stub cannot express conditional return values based on
        # the SQL argument passed to exec_query.
        fake_connection = Class.new do
          def exec_query(sql)
            locked = !sql.include?("pg_try_advisory_lock")
            ActiveRecord::Result.new([], [ [ locked ] ])
          end
        end.new

        ActiveRecord::Base.connection_pool.stub(:with_connection, ->(&block) { block.call(fake_connection) }) do
          assert_raises(SourceMonitor::Fetching::AdvisoryLock::NotAcquiredError) do
            lock.with_lock { flunk "should not yield when lock is busy" }
          end
        end
      end

      test "releases lock when block raises" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        assert_raises(TestError) do
          lock.with_lock { raise TestError, "boom" }
        end

        assert lock_available?(LOCK_NAMESPACE, key), "expected lock to be released when block raises"
      end

      test "acquire! acquires the lock and release! frees it" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        result = lock.acquire!
        assert result, "expected acquire! to return true"

        # Advisory locks are session-scoped and re-entrant, so we can't test
        # "not available" from the same connection. Instead, verify that
        # release! completes without error and the lock lifecycle works.
        lock.release!
        assert lock_available?(LOCK_NAMESPACE, key), "expected lock to be released after release!"
      end

      test "acquire! raises when lock is already held and raise_on_failure is true" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        # Hold the lock in a different connection-like fashion using with_lock
        lock.acquire!
        begin
          # A second lock instance trying to acquire the same key should fail
          lock2 = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

          # Advisory locks are re-entrant on the same session, so we simulate
          # failure by stubbing
          fake_connection = Class.new do
            def exec_query(sql)
              locked = !sql.include?("pg_try_advisory_lock")
              ActiveRecord::Result.new([], [ [ locked ] ])
            end
          end.new

          ActiveRecord::Base.connection_pool.stub(:with_connection, ->(&block) { block.call(fake_connection) }) do
            assert_raises(SourceMonitor::Fetching::AdvisoryLock::NotAcquiredError) do
              lock2.acquire!
            end
          end
        ensure
          lock.release!
        end
      end

      test "acquire! returns false when raise_on_failure is false and lock is busy" do
        key = next_lock_key
        lock = SourceMonitor::Fetching::AdvisoryLock.new(namespace: LOCK_NAMESPACE, key:)

        fake_connection = Class.new do
          def exec_query(sql)
            locked = !sql.include?("pg_try_advisory_lock")
            ActiveRecord::Result.new([], [ [ locked ] ])
          end
        end.new

        ActiveRecord::Base.connection_pool.stub(:with_connection, ->(&block) { block.call(fake_connection) }) do
          result = lock.acquire!(raise_on_failure: false)
          refute result, "expected acquire! to return false when lock is busy"
        end
      end

      private

      def next_lock_key
        @next_lock_key ||= 0
        @next_lock_key += 1
      end

      def lock_available?(namespace, key)
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          result = connection.exec_query("SELECT pg_try_advisory_lock(#{namespace}, #{key})")
          value = result.rows.dig(0, 0)
          # Ensure any test lock does not linger.
          connection.exec_query("SELECT pg_advisory_unlock(#{namespace}, #{key})") if truthy?(value)
          truthy?(value)
        end
      end

      def truthy?(value)
        value == true || value.to_s == "t"
      end
    end
  end
end
