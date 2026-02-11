# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class HTTPSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = HTTPSettings.new
      end

      test "has sensible defaults" do
        assert_equal 15, @settings.timeout
        assert_equal 5, @settings.open_timeout
        assert_equal 5, @settings.max_redirects
        assert_match(/SourceMonitor/, @settings.user_agent)
        assert_nil @settings.proxy
        assert_equal({}, @settings.headers)
        assert_equal 4, @settings.retry_max
        assert_equal 0.5, @settings.retry_interval
      end

      test "reset restores defaults" do
        @settings.timeout = 99
        @settings.proxy = "http://proxy.example.com"
        @settings.reset!

        assert_equal 15, @settings.timeout
        assert_nil @settings.proxy
      end
    end

    class RetentionSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = RetentionSettings.new
      end

      test "defaults to destroy strategy" do
        assert_equal :destroy, @settings.strategy
        assert_nil @settings.items_retention_days
        assert_nil @settings.max_items
      end

      test "sets strategy to soft_delete" do
        @settings.strategy = :soft_delete
        assert_equal :soft_delete, @settings.strategy
      end

      test "sets strategy with string" do
        @settings.strategy = "destroy"
        assert_equal :destroy, @settings.strategy
      end

      test "sets strategy to nil resets to destroy" do
        @settings.strategy = :soft_delete
        @settings.strategy = nil
        assert_equal :destroy, @settings.strategy
      end

      test "raises for invalid strategy" do
        assert_raises(ArgumentError) { @settings.strategy = :archive }
      end

      test "raises for non-symbolizable strategy" do
        assert_raises(ArgumentError) { @settings.strategy = 123 }
      end
    end

    class ModelsTest < ActiveSupport::TestCase
      setup do
        @models = Models.new
      end

      test "default table_name_prefix" do
        assert_equal "sourcemon_", @models.table_name_prefix
      end

      test "provides model definitions for all keys" do
        assert_kind_of ModelDefinition, @models.source
        assert_kind_of ModelDefinition, @models.item
        assert_kind_of ModelDefinition, @models.fetch_log
        assert_kind_of ModelDefinition, @models.scrape_log
        assert_kind_of ModelDefinition, @models.health_check_log
        assert_kind_of ModelDefinition, @models.item_content
        assert_kind_of ModelDefinition, @models.log_entry
      end

      test "for returns definition by name" do
        assert_kind_of ModelDefinition, @models.for(:source)
      end

      test "for raises for unknown model" do
        assert_raises(ArgumentError) { @models.for(:nonexistent) }
      end
    end

    class ScrapingSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = ScrapingSettings.new
      end

      test "has sensible defaults" do
        assert_equal 25, @settings.max_in_flight_per_source
        assert_equal 100, @settings.max_bulk_batch_size
      end

      test "reset restores defaults" do
        @settings.max_in_flight_per_source = 50
        @settings.reset!
        assert_equal 25, @settings.max_in_flight_per_source
      end

      test "rejects nil values" do
        @settings.max_in_flight_per_source = nil
        assert_nil @settings.max_in_flight_per_source
      end

      test "rejects empty string" do
        @settings.max_in_flight_per_source = ""
        assert_nil @settings.max_in_flight_per_source
      end

      test "rejects zero and negative" do
        @settings.max_in_flight_per_source = 0
        assert_nil @settings.max_in_flight_per_source

        @settings.max_bulk_batch_size = -1
        assert_nil @settings.max_bulk_batch_size
      end

      test "accepts string numbers" do
        @settings.max_in_flight_per_source = "10"
        assert_equal 10, @settings.max_in_flight_per_source
      end
    end

    class ValidationDefinitionTest < ActiveSupport::TestCase
      test "symbol handler" do
        vd = ValidationDefinition.new(:check, { on: :create })

        assert vd.symbol?
        assert_equal [ [ :symbol, :check ], { on: :create } ], vd.signature
      end

      test "string handler" do
        vd = ValidationDefinition.new("check", {})

        assert vd.symbol?
        assert_equal [ [ :symbol, :check ], {} ], vd.signature
      end

      test "callable handler" do
        handler = ->(record) { record }
        vd = ValidationDefinition.new(handler, {})

        refute vd.symbol?
        assert_equal [ [ :callable, handler.object_id ], {} ], vd.signature
      end
    end

    class HealthSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = HealthSettings.new
      end

      test "has sensible defaults" do
        assert_equal 20, @settings.window_size
        assert_equal 0.8, @settings.healthy_threshold
        assert_equal 0.5, @settings.warning_threshold
        assert_equal 0.2, @settings.auto_pause_threshold
        assert_equal 0.6, @settings.auto_resume_threshold
        assert_equal 60, @settings.auto_pause_cooldown_minutes
      end

      test "reset restores defaults" do
        @settings.window_size = 50
        @settings.reset!
        assert_equal 20, @settings.window_size
      end
    end

    class FetchingSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = FetchingSettings.new
      end

      test "has sensible defaults" do
        assert_equal 5, @settings.min_interval_minutes
        assert_equal 24 * 60, @settings.max_interval_minutes
        assert_equal 1.25, @settings.increase_factor
        assert_equal 0.75, @settings.decrease_factor
        assert_equal 1.5, @settings.failure_increase_factor
        assert_equal 0.1, @settings.jitter_percent
      end

      test "reset restores defaults" do
        @settings.min_interval_minutes = 99
        @settings.reset!
        assert_equal 5, @settings.min_interval_minutes
      end
    end
  end
end
