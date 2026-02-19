# frozen_string_literal: true

# Enable coverage reporting in CI or when explicitly requested unless disabled.
skip_coverage_flag = ENV.fetch("SOURCE_MONITOR_SKIP_COVERAGE", "")
skip_coverage =
  case skip_coverage_flag.downcase
  when "", "0", "false"
    false
  else
    true
  end

if (ENV["CI"] || ENV["COVERAGE"]) && !skip_coverage
  require "simplecov"

  command_name = ENV.fetch("SIMPLECOV_COMMAND_NAME", "source_monitor:test")
  SimpleCov.command_name command_name
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter %r{^/test/}
  end

  SimpleCov.enable_for_subprocesses true
end

# Ensure host app helper tests don't traverse temporary bundle directories.
ENV["DEFAULT_TEST_EXCLUDE"] ||= "test/{system,dummy,fixtures,tmp}/**/*_test.rb"

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"
require "webmock/minitest"
require "vcr"
require "turbo-rails"
require "action_cable/test_helper"
require "turbo/broadcastable/test_helper"
require "securerandom"
require "minitest/mock"

require "capybara/rails"
require "capybara/minitest"

# Use the lightweight test adapter by default to avoid enqueuing work inline.
ActiveJob::Base.queue_adapter = :test

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  fixtures_root = File.expand_path("fixtures", __dir__)
  ActiveSupport::TestCase.fixture_paths = [ fixtures_root ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = fixtures_root
  ActiveSupport::TestCase.fixtures :all
end

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("vcr_cassettes", __dir__)
  config.hook_into :webmock
  config.ignore_localhost = true
end

WebMock.disable_net_connect!(allow_localhost: true)

class ActiveSupport::TestCase
  worker_count = if ENV["COVERAGE"]
    1
  else
    count = ENV.fetch("SOURCE_MONITOR_TEST_WORKERS", :number_of_processors)
    count = count.to_i if count.is_a?(String) && !count.empty?
    count = :number_of_processors if count.respond_to?(:zero?) && count.zero?
    count
  end
  parallelize(workers: worker_count, with: :threads)
  # Load TestProf AFTER parallelize so its before_all prepend doesn't
  # intercept the call and emit a spurious threads-incompatibility warning.
  require_relative "test_prof"
  self.test_order = :random

  setup do
    # Thread-safe: reset_configuration! replaces @configuration atomically.
    # Each test gets a fresh config object. No concurrent mutation risk since
    # tests read config only after their own setup completes.
    SourceMonitor.reset_configuration!
    # Disable Faraday retry middleware in tests. Without this, tests that
    # stub WebMock to raise Faraday::TimeoutError trigger 4 retries with
    # exponential backoff (0.5s + 1s + 2s + 4s = 7.5s of real sleep).
    SourceMonitor.config.http.retry_max = 0
  end

  # Clean all engine tables in FK-safe order (children before parents).
  # Call this in setup blocks that need a blank-slate database.
  def clean_source_monitor_tables!
    SourceMonitor::LogEntry.delete_all
    SourceMonitor::ScrapeLog.delete_all
    SourceMonitor::FetchLog.delete_all
    SourceMonitor::HealthCheckLog.delete_all
    SourceMonitor::ItemContent.delete_all
    SourceMonitor::Item.delete_all
    SourceMonitor::Source.delete_all
  end

  private

  def create_source!(attributes = {})
    defaults = {
      name: "Test Source",
      feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml",
      website_url: "https://example.com",
      fetch_interval_minutes: 60,
      scraper_adapter: "readability"
    }

    source = SourceMonitor::Source.new(defaults.merge(attributes))
    source.save!(validate: false)
    source
  end

  def with_queue_adapter(adapter)
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    yield
  ensure
    ActiveJob::Base.queue_adapter = previous
  end
end
