# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class RealtimeSettingsTest < ActiveSupport::TestCase
      setup do
        @settings = RealtimeSettings.new
      end

      test "defaults to solid_cable adapter" do
        assert_equal :solid_cable, @settings.adapter
      end

      test "sets adapter to redis" do
        @settings.adapter = :redis
        assert_equal :redis, @settings.adapter
      end

      test "sets adapter to async" do
        @settings.adapter = :async
        assert_equal :async, @settings.adapter
      end

      test "accepts string adapter values" do
        @settings.adapter = "redis"
        assert_equal :redis, @settings.adapter
      end

      test "raises for unsupported adapter" do
        assert_raises(ArgumentError) { @settings.adapter = :kafka }
      end

      test "reset restores defaults" do
        @settings.adapter = :redis
        @settings.redis_url = "redis://localhost"
        @settings.reset!

        assert_equal :solid_cable, @settings.adapter
        assert_nil @settings.redis_url
      end

      test "action_cable_config for solid_cable" do
        config = @settings.action_cable_config
        assert_equal "solid_cable", config[:adapter]
        assert config.key?(:polling_interval)
      end

      test "action_cable_config for redis without url" do
        @settings.adapter = :redis
        config = @settings.action_cable_config

        assert_equal "redis", config[:adapter]
        refute config.key?(:url)
      end

      test "action_cable_config for redis with url" do
        @settings.adapter = :redis
        @settings.redis_url = "redis://localhost:6379"
        config = @settings.action_cable_config

        assert_equal "redis", config[:adapter]
        assert_equal "redis://localhost:6379", config[:url]
      end

      test "action_cable_config for async" do
        @settings.adapter = :async
        config = @settings.action_cable_config

        assert_equal "async", config[:adapter]
      end

      test "solid_cable= assigns options via hash" do
        @settings.solid_cable = { polling_interval: "1.second", autotrim: false }

        assert_equal "1.second", @settings.solid_cable.polling_interval
        assert_equal false, @settings.solid_cable.autotrim
      end

      test "solid_cable options to_h excludes nil values" do
        hash = @settings.solid_cable.to_h
        refute hash.key?(:trim_batch_size)
        refute hash.key?(:connects_to)
      end

      test "solid_cable assign skips nil input" do
        @settings.solid_cable.assign(nil)
        assert_equal "0.1.seconds", @settings.solid_cable.polling_interval
      end

      test "solid_cable reset restores defaults" do
        @settings.solid_cable.autotrim = false
        @settings.solid_cable.reset!
        assert_equal true, @settings.solid_cable.autotrim
      end
    end
  end
end
