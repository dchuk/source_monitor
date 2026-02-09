# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class RequirementsTest < ActiveSupport::TestCase
      test "version requirement evaluates semantic versions" do
        requirement = Requirements::Version.new(">= 3.4.4")

        assert requirement.satisfied?("3.4.4")
        assert requirement.satisfied?(Gem::Version.new("3.4.5"))
        refute requirement.satisfied?("3.3.9")
        refute requirement.satisfied?(nil)
      end

      test "version requirement normalizes node style output" do
        requirement = Requirements::Version.new(">= 18")

        assert requirement.satisfied?("v18.19.0")
        assert_equal Gem::Version.new("18.19.0"), requirement.normalize("v18.19.0")
      end

      test "adapter requirement enforces adapter equality" do
        requirement = Requirements::Adapter.new("postgresql")

        assert requirement.satisfied?("postgresql")
        assert requirement.satisfied?("PostgreSQL")
        refute requirement.satisfied?("sqlite")
        refute requirement.satisfied?(nil)
      end
    end
  end
end
