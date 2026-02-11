# frozen_string_literal: true

module SourceMonitor
  module Setup
    class DependencyChecker
      Dependency = Struct.new(
        :key,
        :name,
        :requirement,
        :detector,
        :remediation,
        keyword_init: true
      )

      Result = Struct.new(
        :key,
        :name,
        :status,
        :current,
        :expected,
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

        def missing?
          status == :missing
        end
      end

      class Summary
        attr_reader :results

        def initialize(results)
          @results = results
        end

        def overall_status
          return :error if errors?
          return :warning if warnings?

          :ok
        end

        def ok?
          overall_status == :ok
        end

        def errors?
          results.any? { |result| result.error? || result.missing? }
        end

        def warnings?
          results.any?(&:warning?)
        end

        def errors
          results.select { |result| result.error? || result.missing? }
        end

        def warnings
          results.select(&:warning?)
        end
      end

      def initialize(dependencies: default_dependencies)
        @dependencies = dependencies
      end

      def call
        Summary.new(@dependencies.map { |dependency| evaluate_dependency(dependency) })
      end

      private

      def evaluate_dependency(dependency)
        current = safe_detect { dependency.detector.call }
        expected = requirement_expected(dependency.requirement)
        status = classify_status(dependency.requirement, current)

        Result.new(
          key: dependency.key,
          name: dependency.name,
          status: status,
          current: normalize(dependency.requirement, current),
          expected: expected,
          remediation: dependency.remediation
        )
      end

      def safe_detect
        yield
      rescue StandardError
        nil
      end

      def classify_status(requirement, current)
        return :missing if current.nil?
        return :ok if requirement.respond_to?(:satisfied?) && requirement.satisfied?(current)

        :error
      end

      def normalize(requirement, value)
        if requirement.respond_to?(:normalize)
          requirement.normalize(value)
        else
          value
        end
      end

      def requirement_expected(requirement)
        requirement.respond_to?(:expected) ? requirement.expected : nil
      end

      def default_dependencies
        [
          Dependency.new(
            key: :ruby,
            name: "Ruby",
            requirement: Requirements::Version.new(">= 3.4.4"),
            detector: -> { Detectors.ruby_version },
            remediation: "Upgrade Ruby to >= 3.4.4"
          ),
          Dependency.new(
            key: :rails,
            name: "Rails",
            requirement: Requirements::Version.new(">= 8.0.2.1"),
            detector: -> { Detectors.rails_version },
            remediation: "Upgrade Rails to >= 8.0.2.1"
          ),
          Dependency.new(
            key: :node,
            name: "Node.js",
            requirement: Requirements::Version.new(">= 18.0.0"),
            detector: -> { Detectors.node_version },
            remediation: "Install Node.js 18 or newer"
          ),
          Dependency.new(
            key: :postgres,
            name: "PostgreSQL Adapter",
            requirement: Requirements::Adapter.new("postgresql"),
            detector: -> { Detectors.postgres_adapter },
            remediation: "Configure the host app to use PostgreSQL before installing SourceMonitor"
          ),
          Dependency.new(
            key: :solid_queue,
            name: "Solid Queue",
            requirement: Requirements::Version.new([ ">= 0.3.0", "< 3.0" ]),
            detector: -> { Detectors.solid_queue_version },
            remediation: "Add the solid_queue gem (>= 0.3, < 3.0) to your host app"
          )
        ]
      end
    end
  end
end
