# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class ScraperRegistryTest < ActiveSupport::TestCase
      setup do
        @registry = ScraperRegistry.new
      end

      test "register and retrieve an adapter by name" do
        @registry.register("readability", SourceMonitor::Scrapers::Readability)

        assert_equal SourceMonitor::Scrapers::Readability, @registry.adapter_for("readability")
      end

      test "register normalizes name to lowercase" do
        @registry.register("Readability", SourceMonitor::Scrapers::Readability)

        assert_equal SourceMonitor::Scrapers::Readability, @registry.adapter_for("readability")
      end

      test "register with symbol name" do
        @registry.register(:readability, SourceMonitor::Scrapers::Readability)

        assert_equal SourceMonitor::Scrapers::Readability, @registry.adapter_for(:readability)
      end

      test "register with string constant name" do
        @registry.register("readability", "SourceMonitor::Scrapers::Readability")

        assert_equal SourceMonitor::Scrapers::Readability, @registry.adapter_for("readability")
      end

      test "register raises for unknown constant string" do
        assert_raises(ArgumentError) do
          @registry.register("bad", "NonExistent::Scraper::XYZ")
        end
      end

      test "register raises for invalid adapter name" do
        assert_raises(ArgumentError) { @registry.register("bad name!", SourceMonitor::Scrapers::Readability) }
      end

      test "unregister removes adapter" do
        @registry.register("readability", SourceMonitor::Scrapers::Readability)
        @registry.unregister("readability")

        assert_nil @registry.adapter_for("readability")
      end

      test "adapter_for returns nil for unknown adapter" do
        assert_nil @registry.adapter_for("unknown")
      end

      test "is enumerable" do
        @registry.register("readability", SourceMonitor::Scrapers::Readability)

        entries = @registry.map { |name, adapter| [ name, adapter ] }
        assert_equal 1, entries.size
        assert_equal "readability", entries.first.first
      end
    end
  end
end
