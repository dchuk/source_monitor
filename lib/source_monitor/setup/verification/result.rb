# frozen_string_literal: true

require "json"

module SourceMonitor
  module Setup
    module Verification
      Result = Struct.new(
        :key,
        :name,
        :status,
        :details,
        :remediation,
        keyword_init: true
      ) do
        def ok?
          status == :ok
        end

        def warning?
          status == :warning
        end

        def error?
          status == :error
        end

        def as_json(_options = nil)
          {
            key: key,
            name: name,
            status: status,
            details: details,
            remediation: remediation
          }
        end
      end

      class Summary
        attr_reader :results

        def initialize(results)
          @results = results
        end

        def overall_status
          return :error if results.any?(&:error?)
          return :warning if results.any?(&:warning?)

          :ok
        end

        def ok?
          overall_status == :ok
        end

        def to_h
          {
            overall_status: overall_status,
            results: results.map(&:as_json)
          }
        end

        def to_json(*args)
          to_h.to_json(*args)
        end
      end
    end
  end
end
