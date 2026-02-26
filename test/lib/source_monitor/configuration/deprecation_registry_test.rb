# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class DeprecationRegistryTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.reset_configuration!
        DeprecationRegistry.clear!
      end

      teardown do
        DeprecationRegistry.clear!
        SourceMonitor.reset_configuration!
      end

      test "register stores entry in registry" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning,
          message: "Use config.http.proxy instead"
        )

        assert DeprecationRegistry.registered?("http.old_proxy_url")
        entry = DeprecationRegistry.entries["http.old_proxy_url"]
        assert_equal "http.old_proxy_url", entry[:path]
        assert_equal "0.5.0", entry[:removed_in]
        assert_equal "http.proxy", entry[:replacement]
        assert_equal :warning, entry[:severity]
      end

      test "warning severity logs deprecation and forwards to replacement" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning,
          message: "Use config.http.proxy instead"
        )

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          SourceMonitor.configure { |c| c.http.old_proxy_url = "socks5://localhost" }
        ensure
          Rails.logger = original_logger
        end

        assert_match(/DEPRECATION/, log_output.string)
        assert_match(/old_proxy_url/, log_output.string)
        assert_match(/0\.5\.0/, log_output.string)
        assert_match(/http\.proxy/, log_output.string)
        assert_equal "socks5://localhost", SourceMonitor.config.http.proxy
      end

      test "warning severity reader forwards to replacement getter" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        SourceMonitor.config.http.proxy = "socks5://localhost"

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          value = SourceMonitor.config.http.old_proxy_url
        ensure
          Rails.logger = original_logger
        end

        assert_equal "socks5://localhost", value
        assert_match(/DEPRECATION/, log_output.string)
      end

      test "error severity raises DeprecatedOptionError on write" do
        DeprecationRegistry.register(
          "http.removed_option",
          removed_in: "0.5.0",
          severity: :error,
          message: "This option was removed. Use X instead"
        )

        error = assert_raises(SourceMonitor::DeprecatedOptionError) do
          SourceMonitor.configure { |c| c.http.removed_option = "value" }
        end

        assert_match(/removed_option/, error.message)
        assert_match(/0\.5\.0/, error.message)
      end

      test "error severity raises DeprecatedOptionError on read" do
        DeprecationRegistry.register(
          "http.removed_option",
          removed_in: "0.5.0",
          severity: :error,
          message: "This option was removed"
        )

        error = assert_raises(SourceMonitor::DeprecatedOptionError) do
          SourceMonitor.config.http.removed_option
        end

        assert_match(/removed_option/, error.message)
      end

      test "clear removes defined methods and entries" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        assert DeprecationRegistry.registered?("http.old_proxy_url")
        assert_respond_to SourceMonitor.config.http, :old_proxy_url

        DeprecationRegistry.clear!

        assert_not DeprecationRegistry.registered?("http.old_proxy_url")
        assert_empty DeprecationRegistry.entries
        assert_not_respond_to SourceMonitor.config.http, :old_proxy_url
      end

      test "top-level option deprecation works" do
        DeprecationRegistry.register(
          "old_queue_prefix",
          removed_in: "0.5.0",
          replacement: "queue_namespace",
          severity: :warning
        )

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          SourceMonitor.configure { |c| c.old_queue_prefix = "my_app" }
        ensure
          Rails.logger = original_logger
        end

        assert_match(/DEPRECATION/, log_output.string)
        assert_match(/old_queue_prefix/, log_output.string)
        assert_equal "my_app", SourceMonitor.config.queue_namespace
      end

      test "no warnings for valid current configuration" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          SourceMonitor.configure { |c| c.http.timeout = 30 }
        ensure
          Rails.logger = original_logger
        end

        assert_no_match(/DEPRECATION/, log_output.string)
      end

      test "multiple deprecations can coexist" do
        DeprecationRegistry.register(
          "http.old_proxy_url",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        DeprecationRegistry.register(
          "fetching.old_interval",
          removed_in: "0.5.0",
          replacement: "fetching.min_interval_minutes",
          severity: :warning
        )

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          SourceMonitor.configure do |c|
            c.http.old_proxy_url = "socks5://localhost"
            c.fetching.old_interval = 10
          end
        ensure
          Rails.logger = original_logger
        end

        assert_match(/old_proxy_url/, log_output.string)
        assert_match(/old_interval/, log_output.string)
      end

      test "skips trap when method already exists on target class" do
        _out, err = capture_io do
          DeprecationRegistry.register(
            "http.timeout",
            removed_in: "0.5.0",
            replacement: "http.proxy",
            severity: :warning
          )
        end

        assert_match(/DeprecationRegistry.*http\.timeout.*already exists/, err)

        entry = DeprecationRegistry.entries["http.timeout"]
        assert entry[:skipped], "Entry should be marked as skipped when method already exists"
      end

      test "raises ArgumentError for unknown severity" do
        assert_raises(ArgumentError) do
          DeprecationRegistry.register(
            "http.bad_option",
            removed_in: "0.5.0",
            severity: :unknown
          )
        end
      end

      test "cross-prefix replacement forwards writer to different settings class" do
        DeprecationRegistry.register(
          "old_proxy",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          SourceMonitor.configure { |c| c.old_proxy = "socks5://localhost" }
        ensure
          Rails.logger = original_logger
        end

        assert_equal "socks5://localhost", SourceMonitor.config.http.proxy
      end

      test "cross-prefix replacement forwards reader to different settings class" do
        DeprecationRegistry.register(
          "old_proxy",
          removed_in: "0.5.0",
          replacement: "http.proxy",
          severity: :warning
        )

        SourceMonitor.config.http.proxy = "socks5://localhost"

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        begin
          value = SourceMonitor.config.old_proxy
        ensure
          Rails.logger = original_logger
        end

        assert_equal "socks5://localhost", value
      end

      test "raises ArgumentError for unknown settings accessor" do
        assert_raises(ArgumentError) do
          DeprecationRegistry.register(
            "nonexistent_section.option",
            removed_in: "0.5.0",
            severity: :warning
          )
        end
      end

      test "check_deprecations! is called during configure" do
        called = false
        SourceMonitor.config.define_singleton_method(:check_deprecations!) do
          called = true
          DeprecationRegistry.check_defaults!(self)
        end

        SourceMonitor.configure { |c| c.http.timeout = 30 }

        assert called, "check_deprecations! should be called during configure"
      end
    end
  end
end
