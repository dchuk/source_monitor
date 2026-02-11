# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class Runner
        def initialize(verifiers: default_verifiers)
          @verifiers = verifiers
        end

        def call
          results = verifiers.map { |verifier| verifier.call }
          Summary.new(results)
        end

        private

        attr_reader :verifiers

        def default_verifiers
          [ SolidQueueVerifier.new, ActionCableVerifier.new ]
        end
      end
    end
  end
end
