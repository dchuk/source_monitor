# frozen_string_literal: true

module SourceMonitor
  module Fetching
    # Wraps Postgres advisory lock usage to provide a small, testable collaborator
    # for coordinating fetch execution across processes.
    class AdvisoryLock
      NotAcquiredError = Class.new(StandardError)

      def initialize(namespace:, key:, connection_pool: ActiveRecord::Base.connection_pool)
        @namespace = namespace
        @key = key
        @connection_pool = connection_pool
      end

      # Block-based API: acquires lock, yields, releases. Holds a DB connection
      # for the entire duration of the block.
      def with_lock
        connection_pool.with_connection do |connection|
          locked = try_lock(connection)
          raise NotAcquiredError, "advisory lock #{namespace}/#{key} busy" unless locked

          begin
            yield
          ensure
            release(connection)
          end
        end
      end

      # Non-blocking acquire: tries to get the advisory lock. Returns true if
      # acquired, false otherwise. Raises NotAcquiredError when raise_on_failure
      # is true (default). The lock is session-scoped -- it stays held until
      # release! is called on the same DB connection, or the connection is closed.
      def acquire!(raise_on_failure: true)
        locked = false
        connection_pool.with_connection do |connection|
          locked = try_lock(connection)
        end
        raise NotAcquiredError, "advisory lock #{namespace}/#{key} busy" if !locked && raise_on_failure

        locked
      end

      # Releases the advisory lock. Safe to call even if the lock is not held.
      # Because advisory locks are session-scoped, this must run on the same
      # connection that acquired the lock. In a connection pool the pool returns
      # the same connection to the same thread, so this works correctly as long
      # as acquire! and release! are called from the same thread.
      def release!
        connection_pool.with_connection do |connection|
          release(connection)
        end
      end

      private

      attr_reader :namespace, :key, :connection_pool

      def try_lock(connection)
        result = connection.exec_query(
          "SELECT pg_try_advisory_lock(#{namespace.to_i}, #{key.to_i})"
        )

        truthy?(result.rows.dig(0, 0))
      end

      def release(connection)
        connection.exec_query(
          "SELECT pg_advisory_unlock(#{namespace.to_i}, #{key.to_i})"
        )
      rescue StandardError
        nil
      end

      def truthy?(value)
        value == true || value.to_s == "t"
      end
    end
  end
end
