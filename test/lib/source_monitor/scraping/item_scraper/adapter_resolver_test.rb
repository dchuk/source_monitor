# frozen_string_literal: true

require "test_helper"
require "source_monitor/scraping/item_scraper/adapter_resolver"

module SourceMonitor
  module Scraping
    class AdapterResolverTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.reset_configuration!
      end

      teardown do
        SourceMonitor.reset_configuration!
      end

      test "resolves adapter registered via configuration" do
        SourceMonitor.configure do |config|
          config.scrapers.register(:custom, RegisteredAdapter)
        end

        resolver = SourceMonitor::Scraping::ItemScraper::AdapterResolver.new(name: "custom", source: create_source!)

        assert_equal RegisteredAdapter, resolver.resolve!
      end

      test "resolves adapter class under SourceMonitor::Scrapers namespace" do
        resolver = SourceMonitor::Scraping::ItemScraper::AdapterResolver.new(name: "readability", source: create_source!)

        assert_equal SourceMonitor::Scrapers::Readability, resolver.resolve!
      end

      test "raises when adapter name contains invalid characters" do
        resolver = SourceMonitor::Scraping::ItemScraper::AdapterResolver.new(name: "invalid-name!", source: create_source!)

        assert_raises(SourceMonitor::Scraping::ItemScraper::UnknownAdapterError) { resolver.resolve! }
      end

      test "raises when adapter constant does not inherit from base class" do
        stub_const("SourceMonitor::Scrapers::Rogue", Class.new)

        resolver = SourceMonitor::Scraping::ItemScraper::AdapterResolver.new(name: "rogue", source: create_source!)

        assert_raises(SourceMonitor::Scraping::ItemScraper::UnknownAdapterError) { resolver.resolve! }
      ensure
        SourceMonitor::Scrapers.send(:remove_const, :Rogue) if SourceMonitor::Scrapers.const_defined?(:Rogue)
      end

      test "raises when adapter cannot be resolved" do
        resolver = SourceMonitor::Scraping::ItemScraper::AdapterResolver.new(name: "missing", source: create_source!)

        assert_raises(SourceMonitor::Scraping::ItemScraper::UnknownAdapterError) { resolver.resolve! }
      end

      private


      def stub_const(name, value)
        names = name.split("::")
        constant_name = names.pop
        namespace = names.inject(Object) do |const, const_name|
          if const.const_defined?(const_name)
            const.const_get(const_name)
          else
            const.const_set(const_name, Module.new)
          end
        end
        namespace.const_set(constant_name, value)
      end

      class RegisteredAdapter < SourceMonitor::Scrapers::Base
        def call
          Result.new(status: :success)
        end
      end
    end
  end
end
