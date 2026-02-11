# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Requirements
      class Version
        attr_reader :requirement

        def initialize(spec)
          @requirement = Gem::Requirement.new(spec)
        end

        def expected
          requirement.to_s
        end

        def normalize(value)
          return if value.blank?

          normalized = value.to_s.strip.sub(/^v/i, "")
          Gem::Version.new(normalized)
        rescue ArgumentError
          nil
        end

        def satisfied?(value)
          version = normalize(value)
          return false unless version

          requirement.satisfied_by?(version)
        end
      end

      class Adapter
        attr_reader :expected

        def initialize(expected)
          @expected = expected.to_s
        end

        def normalize(value)
          value&.to_s
        end

        def satisfied?(value)
          return false if value.blank?

          value.to_s.casecmp(expected).zero?
        end
      end
    end
  end
end
