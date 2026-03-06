# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module SourceMonitor
  module Fetching
    class RetryPolicy
      Decision = Struct.new(
        :retry?,
        :wait,
        :next_attempt,
        :open_circuit?,
        :circuit_until,
        keyword_init: true
      )

      DEFAULTS = {
        timeout: { attempts: 2, wait: 2.minutes, circuit_wait: 1.hour },
        connection: { attempts: 3, wait: 5.minutes, circuit_wait: 1.hour },
        http_429: { attempts: 2, wait: 15.minutes, circuit_wait: 90.minutes },
        http_5xx: { attempts: 2, wait: 10.minutes, circuit_wait: 90.minutes },
        http_4xx: { attempts: 1, wait: 45.minutes, circuit_wait: 2.hours },
        parsing: { attempts: 1, wait: 30.minutes, circuit_wait: 2.hours },
        blocked: { attempts: 1, wait: 1.hour, circuit_wait: 4.hours },
        authentication: { attempts: 1, wait: 1.hour, circuit_wait: 4.hours },
        unexpected: { attempts: 1, wait: 30.minutes, circuit_wait: 2.hours },
        fallback: { attempts: 2, wait: 10.minutes, circuit_wait: 90.minutes }
      }.freeze

      attr_reader :source, :error, :now

      def initialize(source:, error:, now: Time.current)
        @source = source
        @error = error
        @now = now
      end

      def decision
        policy = DEFAULTS[policy_key]
        attempts = policy.fetch(:attempts)
        wait_duration = policy.fetch(:wait)
        circuit_duration = policy.fetch(:circuit_wait)

        current_attempt = source.fetch_retry_attempt.to_i
        next_attempt = current_attempt + 1

        if next_attempt <= attempts
          Decision.new(
            retry?: true,
            wait: wait_duration,
            next_attempt: next_attempt,
            open_circuit?: false,
            circuit_until: nil
          )
        else
          circuit_until = now + circuit_duration
          Decision.new(
            retry?: false,
            wait: circuit_duration,
            next_attempt: 0,
            open_circuit?: true,
            circuit_until: circuit_until
          )
        end
      end

      private

      def policy_key
        return :timeout if error.is_a?(SourceMonitor::Fetching::TimeoutError)
        return :connection if error.is_a?(SourceMonitor::Fetching::ConnectionError)

        if error.is_a?(SourceMonitor::Fetching::HTTPError)
          status = error.status.to_i
          return :http_429 if status == 429
          return :http_5xx if status >= 500
          return :http_4xx if status >= 400
        end

        return :parsing if error.is_a?(SourceMonitor::Fetching::ParsingError)
        return :blocked if error.is_a?(SourceMonitor::Fetching::BlockedError)
        return :authentication if error.is_a?(SourceMonitor::Fetching::AuthenticationError)
        return :unexpected if error.is_a?(SourceMonitor::Fetching::UnexpectedResponseError)

        :fallback
      end
    end
  end
end
