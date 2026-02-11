# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class ModelDefinitionTest < ActiveSupport::TestCase
      setup do
        @definition = ModelDefinition.new
      end

      test "initializes with empty concerns and validations" do
        assert_empty @definition.validations
        assert_empty @definition.each_concern.to_a
      end

      test "include_concern with a module registers it" do
        mod = Module.new
        result = @definition.include_concern(mod)

        assert_equal mod, result
        concerns = @definition.each_concern.to_a
        assert_equal 1, concerns.size
      end

      test "include_concern with a block creates anonymous module" do
        result = @definition.include_concern { def greet; "hi"; end }

        assert_kind_of Module, result
      end

      test "include_concern with a string registers by constant name" do
        result = @definition.include_concern("ActiveModel::Validations")

        assert_equal "ActiveModel::Validations", result
        concerns = @definition.each_concern.to_a
        assert_equal 1, concerns.size
        _sig, resolved = concerns.first
        assert_equal ActiveModel::Validations, resolved
      end

      test "include_concern deduplicates same module" do
        mod = Module.new
        @definition.include_concern(mod)
        @definition.include_concern(mod)

        assert_equal 1, @definition.each_concern.to_a.size
      end

      test "include_concern with integer uses string representation" do
        result = @definition.include_concern(123)
        assert_equal 123, result
      end

      test "validate with a block registers validation" do
        @definition.validate { |record| record.errors.add(:base, "bad") }

        assert_equal 1, @definition.validations.size
      end

      test "validate with a callable registers validation" do
        handler = ->(record) { record.errors.add(:base, "bad") }
        @definition.validate(handler)

        assert_equal 1, @definition.validations.size
      end

      test "validate with a symbol registers validation" do
        @definition.validate(:check_something)

        assert_equal 1, @definition.validations.size
        assert @definition.validations.first.symbol?
      end

      test "validate with a string registers validation" do
        @definition.validate("check_something")

        assert_equal 1, @definition.validations.size
        assert @definition.validations.first.symbol?
      end

      test "validate raises for invalid handler" do
        assert_raises(ArgumentError) { @definition.validate(123) }
      end

      test "each_concern resolves string constants lazily" do
        @definition.include_concern("ActiveModel::Validations")

        resolved_concerns = []
        @definition.each_concern { |sig, mod| resolved_concerns << [ sig, mod ] }

        assert_equal 1, resolved_concerns.size
        assert_equal ActiveModel::Validations, resolved_concerns.first.last
      end

      test "each_concern raises for unknown constant" do
        @definition.include_concern("NonExistent::Module::XYZ")

        assert_raises(ArgumentError) do
          @definition.each_concern { |_sig, _mod| }
        end
      end
    end
  end
end
