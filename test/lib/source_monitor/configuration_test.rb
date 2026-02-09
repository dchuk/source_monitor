# frozen_string_literal: true

require "test_helper"
require "ostruct"

module SourceMonitor
  class ConfigurationTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
    end

    teardown do
      SourceMonitor.reset_configuration!
    end

    test "mission control dashboard path resolves nil when route missing" do
      SourceMonitor.configure do |config|
        config.mission_control_dashboard_path = "/mission_control"
      end

      assert_nil SourceMonitor.mission_control_dashboard_path
    end

    test "mission control dashboard path resolves callable when route exists" do
      SourceMonitor.configure do |config|
        config.mission_control_dashboard_path = -> { SourceMonitor::Engine.routes.url_helpers.root_path }
      end

      assert_nothing_raised do
        Rails.application.routes.recognize_path(SourceMonitor::Engine.routes.url_helpers.root_path, method: :get)
      end

      assert_equal SourceMonitor::Engine.routes.url_helpers.root_path, SourceMonitor.mission_control_dashboard_path
    end

    test "mission control dashboard path allows external URLs" do
      SourceMonitor.configure do |config|
        config.mission_control_dashboard_path = "https://status.example.com/mission-control"
      end

      assert_equal "https://status.example.com/mission-control", SourceMonitor.mission_control_dashboard_path
    end

    test "scraper registry returns configured adapters" do
      SourceMonitor.configure do |config|
        config.scrapers.register(:custom_readability, SourceMonitor::Scrapers::Readability)
      end

      adapter = SourceMonitor.config.scrapers.adapter_for("custom_readability")
      assert_equal SourceMonitor::Scrapers::Readability, adapter
    end

    test "retention settings default to destroy strategy" do
      assert_equal :destroy, SourceMonitor.config.retention.strategy

      SourceMonitor.configure do |config|
        config.retention.strategy = :soft_delete
      end

      assert_equal :soft_delete, SourceMonitor.config.retention.strategy
    end

    test "fetching settings expose defaults and allow overrides" do
      settings = SourceMonitor.config.fetching
      assert_equal 5, settings.min_interval_minutes
      assert_equal 24 * 60, settings.max_interval_minutes
      assert_equal 1.25, settings.increase_factor
      assert_equal 0.75, settings.decrease_factor
      assert_equal 1.5, settings.failure_increase_factor
      assert_equal 0.1, settings.jitter_percent

      SourceMonitor.configure do |config|
        config.fetching.min_interval_minutes = 15
        config.fetching.max_interval_minutes = 720
        config.fetching.increase_factor = 1.4
        config.fetching.decrease_factor = 0.6
        config.fetching.failure_increase_factor = 2.2
        config.fetching.jitter_percent = 0.05
      end

      updated = SourceMonitor.config.fetching
      assert_equal 15, updated.min_interval_minutes
      assert_equal 720, updated.max_interval_minutes
      assert_in_delta 1.4, updated.increase_factor
      assert_in_delta 0.6, updated.decrease_factor
      assert_in_delta 2.2, updated.failure_increase_factor
      assert_in_delta 0.05, updated.jitter_percent
    end

    # =========================================================================
    # Task 1: AuthenticationSettings handlers (lines 75-130)
    # =========================================================================

    test "authenticate_with symbol handler dispatches via public_send" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with :authenticate_user!
      end

      handler = SourceMonitor.config.authentication.authenticate_handler
      assert_equal :symbol, handler.type
      assert_equal :authenticate_user!, handler.callable

      controller = OpenStruct.new
      controller.define_singleton_method(:authenticate_user!) { :authenticated }
      assert_equal :authenticated, handler.call(controller)
    end

    test "authenticate_with string handler converts to symbol" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with "authenticate_user!"
      end

      handler = SourceMonitor.config.authentication.authenticate_handler
      assert_equal :symbol, handler.type
      assert_equal :authenticate_user!, handler.callable
    end

    test "authenticate_with callable handler with zero arity uses instance_exec" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with ->() { self.class.name }
      end

      handler = SourceMonitor.config.authentication.authenticate_handler
      assert_equal :callable, handler.type

      controller = OpenStruct.new
      result = handler.call(controller)
      assert_equal "OpenStruct", result
    end

    test "authenticate_with callable handler with arity passes controller" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with ->(ctrl) { ctrl }
      end

      handler = SourceMonitor.config.authentication.authenticate_handler
      controller = OpenStruct.new(name: "test_controller")
      assert_equal controller, handler.call(controller)
    end

    test "authenticate_with block handler" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with { :from_block }
      end

      handler = SourceMonitor.config.authentication.authenticate_handler
      controller = OpenStruct.new
      assert_equal :from_block, handler.call(controller)
    end

    test "authorize_with symbol handler dispatches via public_send" do
      SourceMonitor.configure do |config|
        config.authentication.authorize_with :authorize_admin!
      end

      handler = SourceMonitor.config.authentication.authorize_handler
      assert_equal :symbol, handler.type

      controller = OpenStruct.new
      controller.define_singleton_method(:authorize_admin!) { :authorized }
      assert_equal :authorized, handler.call(controller)
    end

    test "authorize_with callable handler" do
      SourceMonitor.configure do |config|
        config.authentication.authorize_with ->(ctrl) { ctrl.class.name }
      end

      handler = SourceMonitor.config.authentication.authorize_handler
      assert_equal :callable, handler.type
      controller = OpenStruct.new
      assert_equal "OpenStruct", handler.call(controller)
    end

    test "handler call returns nil when callable is nil" do
      handler = SourceMonitor::Configuration::AuthenticationSettings::Handler.new(:symbol, nil)
      assert_nil handler.call(OpenStruct.new)
    end

    test "build_handler raises on invalid handler type" do
      assert_raises(ArgumentError, /Invalid authentication handler/) do
        SourceMonitor.configure do |config|
          config.authentication.authenticate_with 42
        end
      end
    end

    test "authentication reset clears all handlers and methods" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with :auth!
        config.authentication.authorize_with :authz!
        config.authentication.current_user_method = :current_admin
        config.authentication.user_signed_in_method = :admin_signed_in?
      end

      auth = SourceMonitor.config.authentication
      assert_not_nil auth.authenticate_handler
      assert_not_nil auth.authorize_handler
      assert_equal :current_admin, auth.current_user_method
      assert_equal :admin_signed_in?, auth.user_signed_in_method

      auth.reset!

      assert_nil auth.authenticate_handler
      assert_nil auth.authorize_handler
      assert_nil auth.current_user_method
      assert_nil auth.user_signed_in_method
    end

    test "authenticate_with nil returns nil handler" do
      SourceMonitor.configure do |config|
        config.authentication.authenticate_with nil
      end

      assert_nil SourceMonitor.config.authentication.authenticate_handler
    end

    # =========================================================================
    # Task 2: ScrapingSettings and RetentionSettings edge cases (lines 132-164, 398-436)
    # =========================================================================

    test "scraping settings have correct defaults" do
      settings = SourceMonitor.config.scraping
      assert_equal 25, settings.max_in_flight_per_source
      assert_equal 100, settings.max_bulk_batch_size
    end

    test "scraping settings normalize string values to integers" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = "10"
        config.scraping.max_bulk_batch_size = "50"
      end

      settings = SourceMonitor.config.scraping
      assert_equal 10, settings.max_in_flight_per_source
      assert_equal 50, settings.max_bulk_batch_size
    end

    test "scraping settings normalize nil to nil" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = nil
        config.scraping.max_bulk_batch_size = nil
      end

      settings = SourceMonitor.config.scraping
      assert_nil settings.max_in_flight_per_source
      assert_nil settings.max_bulk_batch_size
    end

    test "scraping settings normalize empty string to nil" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = ""
        config.scraping.max_bulk_batch_size = ""
      end

      settings = SourceMonitor.config.scraping
      assert_nil settings.max_in_flight_per_source
      assert_nil settings.max_bulk_batch_size
    end

    test "scraping settings normalize zero to nil" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = 0
        config.scraping.max_bulk_batch_size = 0
      end

      settings = SourceMonitor.config.scraping
      assert_nil settings.max_in_flight_per_source
      assert_nil settings.max_bulk_batch_size
    end

    test "scraping settings normalize negative values to nil" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = -5
        config.scraping.max_bulk_batch_size = -1
      end

      settings = SourceMonitor.config.scraping
      assert_nil settings.max_in_flight_per_source
      assert_nil settings.max_bulk_batch_size
    end

    test "scraping settings reset restores defaults" do
      SourceMonitor.configure do |config|
        config.scraping.max_in_flight_per_source = 5
        config.scraping.max_bulk_batch_size = 10
      end

      SourceMonitor.config.scraping.reset!

      settings = SourceMonitor.config.scraping
      assert_equal 25, settings.max_in_flight_per_source
      assert_equal 100, settings.max_bulk_batch_size
    end

    test "retention settings default to nil for days and max_items" do
      retention = SourceMonitor.config.retention
      assert_nil retention.items_retention_days
      assert_nil retention.max_items
    end

    test "retention strategy defaults to destroy" do
      assert_equal :destroy, SourceMonitor.config.retention.strategy
    end

    test "retention strategy accepts soft_delete" do
      SourceMonitor.configure do |config|
        config.retention.strategy = :soft_delete
      end

      assert_equal :soft_delete, SourceMonitor.config.retention.strategy
    end

    test "retention strategy accepts string values" do
      SourceMonitor.configure do |config|
        config.retention.strategy = "destroy"
      end

      assert_equal :destroy, SourceMonitor.config.retention.strategy
    end

    test "retention strategy rejects invalid value" do
      assert_raises(ArgumentError, /Invalid retention strategy/) do
        SourceMonitor.configure do |config|
          config.retention.strategy = :archive
        end
      end
    end

    test "retention strategy rejects non-symbolizable value" do
      assert_raises(ArgumentError, /Invalid retention strategy/) do
        SourceMonitor.configure do |config|
          config.retention.strategy = 42
        end
      end
    end

    test "retention strategy normalizes nil to destroy" do
      SourceMonitor.configure do |config|
        config.retention.strategy = :soft_delete
      end
      assert_equal :soft_delete, SourceMonitor.config.retention.strategy

      SourceMonitor.configure do |config|
        config.retention.strategy = nil
      end
      assert_equal :destroy, SourceMonitor.config.retention.strategy
    end

    # =========================================================================
    # Task 3: RealtimeSettings adapter validation and action_cable_config (lines 166-253)
    # =========================================================================

    test "realtime settings default to solid_cable adapter" do
      settings = SourceMonitor.config.realtime
      assert_equal :solid_cable, settings.adapter
      assert_nil settings.redis_url
    end

    test "realtime settings accept valid adapters" do
      %i[solid_cable redis async].each do |adapter|
        SourceMonitor.configure do |config|
          config.realtime.adapter = adapter
        end
        assert_equal adapter, SourceMonitor.config.realtime.adapter
      end
    end

    test "realtime settings accept string adapter values" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = "redis"
      end
      assert_equal :redis, SourceMonitor.config.realtime.adapter
    end

    test "realtime settings reject invalid adapter" do
      assert_raises(ArgumentError, /Unsupported realtime adapter/) do
        SourceMonitor.configure do |config|
          config.realtime.adapter = :websocket
        end
      end
    end

    test "realtime settings reject nil adapter" do
      assert_raises(ArgumentError, /Unsupported realtime adapter/) do
        SourceMonitor.configure do |config|
          config.realtime.adapter = nil
        end
      end
    end

    test "action_cable_config for solid_cable returns merged options" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = :solid_cable
      end

      cable_config = SourceMonitor.config.realtime.action_cable_config
      assert_equal "solid_cable", cable_config[:adapter]
      assert_equal "0.1.seconds", cable_config[:polling_interval]
      assert_equal "1.day", cable_config[:message_retention]
      assert_equal true, cable_config[:autotrim]
      assert_equal true, cable_config[:silence_polling]
      assert_equal true, cable_config[:use_skip_locked]
      assert_nil cable_config[:trim_batch_size]
      assert_nil cable_config[:connects_to]
    end

    test "action_cable_config for redis without url" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = :redis
      end

      cable_config = SourceMonitor.config.realtime.action_cable_config
      assert_equal({ adapter: "redis" }, cable_config)
    end

    test "action_cable_config for redis with url" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = :redis
        config.realtime.redis_url = "redis://localhost:6379/1"
      end

      cable_config = SourceMonitor.config.realtime.action_cable_config
      assert_equal "redis", cable_config[:adapter]
      assert_equal "redis://localhost:6379/1", cable_config[:url]
    end

    test "action_cable_config for async" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = :async
      end

      cable_config = SourceMonitor.config.realtime.action_cable_config
      assert_equal({ adapter: "async" }, cable_config)
    end

    test "solid_cable options can be assigned via hash" do
      SourceMonitor.configure do |config|
        config.realtime.solid_cable = {
          polling_interval: "0.5.seconds",
          message_retention: "2.days",
          autotrim: false,
          silence_polling: false,
          trim_batch_size: 500,
          connects_to: { database: :cable }
        }
      end

      options = SourceMonitor.config.realtime.solid_cable
      assert_equal "0.5.seconds", options.polling_interval
      assert_equal "2.days", options.message_retention
      assert_equal false, options.autotrim
      assert_equal false, options.silence_polling
      assert_equal 500, options.trim_batch_size
      assert_equal({ database: :cable }, options.connects_to)
    end

    test "solid_cable assign ignores unknown keys" do
      SourceMonitor.configure do |config|
        config.realtime.solid_cable = { unknown_key: "ignored", polling_interval: "2.seconds" }
      end

      assert_equal "2.seconds", SourceMonitor.config.realtime.solid_cable.polling_interval
    end

    test "solid_cable assign handles non-enumerable input" do
      SourceMonitor.configure do |config|
        config.realtime.solid_cable = nil
      end

      # Should not raise and should keep defaults
      assert_equal "0.1.seconds", SourceMonitor.config.realtime.solid_cable.polling_interval
    end

    test "solid_cable to_h compacts nil values" do
      options = SourceMonitor.config.realtime.solid_cable
      hash = options.to_h

      assert_not_includes hash.keys, :trim_batch_size
      assert_not_includes hash.keys, :connects_to
      assert_includes hash.keys, :polling_interval
      assert_includes hash.keys, :autotrim
    end

    test "realtime reset restores defaults" do
      SourceMonitor.configure do |config|
        config.realtime.adapter = :redis
        config.realtime.redis_url = "redis://localhost:6379"
        config.realtime.solid_cable = { polling_interval: "5.seconds" }
      end

      SourceMonitor.config.realtime.reset!

      settings = SourceMonitor.config.realtime
      assert_equal :solid_cable, settings.adapter
      assert_nil settings.redis_url
      assert_equal "0.1.seconds", settings.solid_cable.polling_interval
    end

    # =========================================================================
    # Task 4: Events callbacks and item_processors (lines 438-491)
    # =========================================================================

    test "events register after_item_created callback with lambda" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_item_created).size
      called = false
      SourceMonitor.configure do |config|
        config.events.after_item_created ->(_item) { called = true }
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_item_created)
      assert_equal baseline + 1, callbacks.size
      callbacks.last.call(nil)
      assert called
    end

    test "events register after_item_created callback with block" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_item_created).size
      called = false
      SourceMonitor.configure do |config|
        config.events.after_item_created { |_item| called = true }
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_item_created)
      assert_equal baseline + 1, callbacks.size
      callbacks.last.call(nil)
      assert called
    end

    test "events register after_item_scraped callback" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_item_scraped).size
      processor = ->(item) { item }
      SourceMonitor.configure do |config|
        config.events.after_item_scraped processor
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_item_scraped)
      assert_equal baseline + 1, callbacks.size
      assert_equal processor, callbacks.last
    end

    test "events register after_fetch_completed callback" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_fetch_completed).size
      processor = ->(result) { result }
      SourceMonitor.configure do |config|
        config.events.after_fetch_completed processor
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_fetch_completed)
      assert_equal baseline + 1, callbacks.size
    end

    test "events register multiple callbacks for same event" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_item_created).size
      SourceMonitor.configure do |config|
        config.events.after_item_created ->(_) { :first }
        config.events.after_item_created ->(_) { :second }
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_item_created)
      assert_equal baseline + 2, callbacks.size
    end

    test "events callbacks_for returns empty array for unknown event key" do
      callbacks = SourceMonitor.config.events.callbacks_for(:nonexistent_event)
      assert_equal [], callbacks
    end

    test "events callbacks_for returns dup preventing external mutation" do
      baseline = SourceMonitor.config.events.callbacks_for(:after_item_created).size
      SourceMonitor.configure do |config|
        config.events.after_item_created ->(_) { :first }
      end

      callbacks = SourceMonitor.config.events.callbacks_for(:after_item_created)
      callbacks.clear

      assert_equal baseline + 1, SourceMonitor.config.events.callbacks_for(:after_item_created).size
    end

    test "events reject non-callable handler" do
      assert_raises(ArgumentError, /handler must respond to #call/) do
        SourceMonitor.configure do |config|
          config.events.after_item_created :not_callable
        end
      end
    end

    test "events register_item_processor with lambda" do
      processor = ->(item) { item.merge(processed: true) }
      SourceMonitor.configure do |config|
        config.events.register_item_processor processor
      end

      processors = SourceMonitor.config.events.item_processors
      assert_equal 1, processors.size
      assert_equal processor, processors.first
    end

    test "events register_item_processor with block" do
      SourceMonitor.configure do |config|
        config.events.register_item_processor { |item| item }
      end

      processors = SourceMonitor.config.events.item_processors
      assert_equal 1, processors.size
    end

    test "events register multiple item_processors" do
      SourceMonitor.configure do |config|
        config.events.register_item_processor ->(item) { item }
        config.events.register_item_processor ->(item) { item }
      end

      assert_equal 2, SourceMonitor.config.events.item_processors.size
    end

    test "events item_processors returns dup preventing external mutation" do
      SourceMonitor.configure do |config|
        config.events.register_item_processor ->(item) { item }
      end

      processors = SourceMonitor.config.events.item_processors
      processors.clear

      assert_equal 1, SourceMonitor.config.events.item_processors.size
    end

    test "events reject non-callable item_processor" do
      assert_raises(ArgumentError, /handler must respond to #call/) do
        SourceMonitor.configure do |config|
          config.events.register_item_processor :not_callable
        end
      end
    end

    test "events reset clears callbacks and item_processors" do
      SourceMonitor.configure do |config|
        config.events.after_item_created ->(_) { :callback }
        config.events.register_item_processor ->(item) { item }
      end

      assert_operator SourceMonitor.config.events.callbacks_for(:after_item_created).size, :>=, 1
      assert_operator SourceMonitor.config.events.item_processors.size, :>=, 1

      SourceMonitor.config.events.reset!

      assert_equal 0, SourceMonitor.config.events.callbacks_for(:after_item_created).size
      assert_equal 0, SourceMonitor.config.events.item_processors.size
    end

    # =========================================================================
    # Task 5: Models, ModelDefinition, ConcernDefinition, ValidationDefinition (lines 493-652)
    # =========================================================================

    test "models default table_name_prefix" do
      assert_equal "sourcemon_", SourceMonitor.config.models.table_name_prefix
    end

    test "models expose all model keys as methods" do
      models = SourceMonitor.config.models
      %i[source item fetch_log scrape_log health_check_log item_content log_entry].each do |key|
        assert_respond_to models, key
        assert_instance_of SourceMonitor::Configuration::ModelDefinition, models.send(key)
      end
    end

    test "models for method returns definition by name" do
      models = SourceMonitor.config.models
      assert_equal models.source, models.for(:source)
      assert_equal models.item, models.for(:item)
      assert_equal models.fetch_log, models.for("fetch_log")
    end

    test "models for raises on unknown model" do
      assert_raises(ArgumentError, /Unknown model/) do
        SourceMonitor.config.models.for(:nonexistent)
      end
    end

    test "model definition include_concern with module" do
      test_concern = Module.new do
        def self.name
          "TestConcern"
        end
      end

      definition = SourceMonitor::Configuration::ModelDefinition.new
      result = definition.include_concern(test_concern)

      assert_equal test_concern, result

      concerns = definition.each_concern.to_a
      assert_equal 1, concerns.size
      signature, resolved = concerns.first
      assert_equal [:module, test_concern.object_id], signature
      assert_equal test_concern, resolved
    end

    test "model definition include_concern with block" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      result = definition.include_concern do
        def custom_method
          "custom"
        end
      end

      assert_kind_of Module, result

      concerns = definition.each_concern.to_a
      assert_equal 1, concerns.size
      _signature, resolved = concerns.first
      assert_kind_of Module, resolved
      assert resolved.instance_methods.include?(:custom_method)
    end

    test "model definition include_concern with string constant" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      result = definition.include_concern("ActiveSupport::Concern")

      assert_equal "ActiveSupport::Concern", result

      concerns = definition.each_concern.to_a
      assert_equal 1, concerns.size
      signature, resolved = concerns.first
      assert_equal [:constant, "ActiveSupport::Concern"], signature
      assert_equal ActiveSupport::Concern, resolved
    end

    test "model definition include_concern with invalid string raises on resolve" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      definition.include_concern("NonExistent::FakeModule")

      assert_raises(ArgumentError) do
        definition.each_concern.to_a
      end
    end

    test "model definition include_concern with numeric takes string path and fails on resolve" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      # 42.to_s => "42", so it takes the string constant path without raising at registration
      definition.include_concern(42)

      # But resolving triggers constantize("42") which fails
      assert_raises(ArgumentError) do
        definition.each_concern.to_a
      end
    end

    test "model definition include_concern deduplicates by signature" do
      test_concern = Module.new
      definition = SourceMonitor::Configuration::ModelDefinition.new

      definition.include_concern(test_concern)
      definition.include_concern(test_concern)

      concerns = definition.each_concern.to_a
      assert_equal 1, concerns.size
    end

    test "model definition include_concern does not deduplicate different blocks" do
      definition = SourceMonitor::Configuration::ModelDefinition.new

      definition.include_concern { def a; end }
      definition.include_concern { def b; end }

      concerns = definition.each_concern.to_a
      assert_equal 2, concerns.size
    end

    test "model definition include_concern deduplicates same string constant" do
      definition = SourceMonitor::Configuration::ModelDefinition.new

      definition.include_concern("ActiveSupport::Concern")
      definition.include_concern("ActiveSupport::Concern")

      concerns = definition.each_concern.to_a
      assert_equal 1, concerns.size
    end

    test "model definition each_concern returns enumerator without block" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      enum = definition.each_concern
      assert_kind_of Enumerator, enum
    end

    test "model definition validate with symbol" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      validation = definition.validate(:custom_validation, if: :active?)

      assert_instance_of SourceMonitor::Configuration::ValidationDefinition, validation
      assert_equal :custom_validation, validation.handler
      assert_equal({ if: :active? }, validation.options)
      assert validation.symbol?
    end

    test "model definition validate with string" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      validation = definition.validate("custom_validation")

      assert_equal :custom_validation, validation.handler
      assert validation.symbol?
    end

    test "model definition validate with lambda" do
      validator = ->(record) { record.errors.add(:base, "invalid") }
      definition = SourceMonitor::Configuration::ModelDefinition.new
      validation = definition.validate(validator)

      assert_equal validator, validation.handler
      assert_not validation.symbol?
    end

    test "model definition validate with block" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      validation = definition.validate { |record| record.errors.add(:base, "invalid") }

      assert_not validation.symbol?
      assert validation.handler.respond_to?(:call)
    end

    test "model definition validate raises on invalid handler" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      assert_raises(ArgumentError, /Invalid validation handler/) do
        definition.validate(42)
      end
    end

    test "model definition stores multiple validations" do
      definition = SourceMonitor::Configuration::ModelDefinition.new
      definition.validate(:first_validation)
      definition.validate(:second_validation, on: :create)
      definition.validate { |_record| true }

      assert_equal 3, definition.validations.size
    end

    test "validation definition signature for symbol handler" do
      validation = SourceMonitor::Configuration::ValidationDefinition.new(:check, { if: :ready? })
      signature = validation.signature

      assert_equal [[:symbol, :check], { if: :ready? }], signature
    end

    test "validation definition signature for string handler" do
      validation = SourceMonitor::Configuration::ValidationDefinition.new("check", {})
      signature = validation.signature

      assert_equal [[:symbol, :check], {}], signature
    end

    test "validation definition signature for callable handler" do
      handler = ->(r) { r }
      validation = SourceMonitor::Configuration::ValidationDefinition.new(handler, {})
      signature = validation.signature

      assert_equal [[:callable, handler.object_id], {}], signature
    end
  end
end
