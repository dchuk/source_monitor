# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "rails/generators/test_case"
require "generators/source_monitor/install/install_generator"

module SourceMonitor
  class InstallGeneratorTest < Rails::Generators::TestCase
    tests SourceMonitor::Generators::InstallGenerator
    WORKER_SUFFIX = begin
      value = ENV.fetch("TEST_ENV_NUMBER", "")
      value.empty? ? "" : "_worker_#{value}"
    end

    destination File.expand_path("../tmp/install_generator#{WORKER_SUFFIX}", __dir__)

    def setup
      super
      prepare_destination
      write_routes_file
    end

    def test_generator_class_exists
      assert_kind_of Class, SourceMonitor::Generators::InstallGenerator
    end

    def test_mounts_engine_with_default_path
      run_generator
      assert_file "config/routes.rb", /mount SourceMonitor::Engine, at: "\/source_monitor"/
    end

    def test_mounts_engine_with_custom_path
      run_generator [ "--mount-path=/reader" ]
      assert_file "config/routes.rb", /mount SourceMonitor::Engine, at: "\/reader"/
    end

    def test_mount_path_without_leading_slash_is_normalized
      run_generator [ "--mount-path=admin/source_monitor" ]
      assert_file "config/routes.rb", /mount SourceMonitor::Engine, at: "\/admin\/source_monitor"/
    end

    def test_creates_initializer_with_commented_defaults
      run_generator

      assert_file "config/initializers/source_monitor.rb" do |content|
        assert_match(/SourceMonitor.configure do \|config\|/, content)
        assert_match(/config.queue_namespace = "source_monitor"/, content)
        assert_match(/config.fetch_queue_name = "\#\{config.queue_namespace\}_fetch"/, content)
        assert_match(/config.scrape_queue_name = "\#\{config.queue_namespace\}_scrape"/, content)
        assert_match(/config.fetch_queue_concurrency = 2/, content)
        assert_match(/config.scrape_queue_concurrency = 2/, content)
        assert_match(/config.job_metrics_enabled = true/, content)
        assert_match(/config.mission_control_enabled = false/, content)
        assert_match(/config.mission_control_dashboard_path = nil/, content)
        assert_match(/config.health.window_size = 20/, content)
        assert_match(/config.health.auto_pause_threshold = 0.2/, content)
        assert_match(/config\.scraping\.max_in_flight_per_source/, content)
        assert_match(/config\.scraping\.max_bulk_batch_size/, content)
      end
    end

    def test_does_not_overwrite_existing_initializer
      initializer_path = File.join(destination_root, "config/initializers")
      FileUtils.mkdir_p(initializer_path)
      File.write(File.join(initializer_path, "source_monitor.rb"), "# existing")

      run_generator

      assert_file "config/initializers/source_monitor.rb", /# existing/
    end

    def test_does_not_duplicate_routes_when_rerun
      run_generator
      run_generator

      routes_contents = File.read(File.join(destination_root, "config/routes.rb"))
      assert_equal 1, routes_contents.scan(/mount SourceMonitor::Engine/).count
    end

    def test_outputs_next_steps_with_doc_links
      output = run_generator

      assert_includes output, "docs/setup.md"
      assert_includes output, "docs/troubleshooting.md"
    end

    def test_creates_recurring_yml_when_none_exists
      run_generator

      assert_file "config/recurring.yml" do |content|
        assert_match(/default: &default/, content)
        assert_match(/source_monitor_schedule_fetches/, content)
        assert_match(/source_monitor_schedule_scrapes/, content)
        assert_match(/source_monitor_item_cleanup/, content)
        assert_match(/source_monitor_log_cleanup/, content)
        assert_match(/development:/, content)
        assert_match(/test:/, content)
        assert_match(/production:/, content)
      end
    end

    def test_merges_into_existing_recurring_yml_with_default_key
      recurring_path = File.join(destination_root, "config")
      FileUtils.mkdir_p(recurring_path)
      File.write(File.join(recurring_path, "recurring.yml"), <<~YAML)
        default: &default
          my_existing_job:
            class: MyJob
            schedule: every hour

        development:
          <<: *default
      YAML

      run_generator

      assert_file "config/recurring.yml" do |content|
        assert_match(/source_monitor_schedule_fetches/, content)
        assert_match(/source_monitor_item_cleanup/, content)
        assert_match(/default: &default/, content)
      end
    end

    def test_merges_into_existing_recurring_yml_without_default_key
      recurring_path = File.join(destination_root, "config")
      FileUtils.mkdir_p(recurring_path)
      File.write(File.join(recurring_path, "recurring.yml"), <<~YAML)
        my_existing_job:
          class: MyJob
          schedule: every hour
      YAML

      run_generator

      assert_file "config/recurring.yml" do |content|
        assert_match(/source_monitor_schedule_fetches/, content)
        assert_match(/my_existing_job/, content)
      end
    end

    def test_skips_recurring_yml_when_entries_already_present
      recurring_path = File.join(destination_root, "config")
      FileUtils.mkdir_p(recurring_path)
      File.write(File.join(recurring_path, "recurring.yml"), <<~YAML)
        default: &default
          source_monitor_schedule_fetches:
            class: SourceMonitor::ScheduleFetchesJob
            schedule: every minute
      YAML

      output = run_generator

      assert_match(/skip/, output)
    end

    private

    def write_routes_file
      routes_path = File.join(destination_root, "config")
      FileUtils.mkdir_p(routes_path)
      File.write(File.join(routes_path, "routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
        end
      RUBY
    end
  end
end
