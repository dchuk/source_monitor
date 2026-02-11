# frozen_string_literal: true

require "yaml"
require "rails/generators"
require "rails/generators/base"

module SourceMonitor
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :mount_path,
        type: :string,
        default: "/source_monitor",
        desc: "Path the engine will mount at inside the host application's routes"

      def add_routes_mount
        mount_path = normalized_mount_path
        return if engine_already_mounted?(mount_path)

        route %(mount SourceMonitor::Engine, at: "#{mount_path}")
      end

      def create_initializer
        initializer_path = "config/initializers/source_monitor.rb"
        destination = File.join(destination_root, initializer_path)

        if File.exist?(destination)
          say_status :skip, initializer_path, :yellow
          return
        end

        template "source_monitor.rb.tt", initializer_path
      end

      def configure_recurring_jobs
        recurring_path = "config/recurring.yml"
        destination = File.join(destination_root, recurring_path)

        if recurring_file_has_source_monitor_entries?(destination)
          say_status :skip, "#{recurring_path} (SourceMonitor entries already present)", :yellow
          return
        end

        if File.exist?(destination)
          merge_into_existing_recurring(destination, recurring_path)
        else
          create_recurring_file(destination, recurring_path)
        end
      end

      def patch_procfile_dev
        procfile_path = File.join(destination_root, "Procfile.dev")

        if File.exist?(procfile_path)
          content = File.read(procfile_path)
          if content.match?(/^jobs:/)
            say_status :skip, "Procfile.dev (jobs entry already present)", :yellow
            return
          end

          File.open(procfile_path, "a") { |f| f.puts("", PROCFILE_JOBS_ENTRY) }
          say_status :append, "Procfile.dev", :green
        else
          File.write(procfile_path, "web: bin/rails server -p 3000\n#{PROCFILE_JOBS_ENTRY}\n")
          say_status :create, "Procfile.dev", :green
        end
      end

      def print_next_steps
        say_status :info,
          "Procfile.dev configured — run bin/dev to start both web server and Solid Queue workers.",
          :green
        say_status :info,
          "Recurring jobs configured in config/recurring.yml — they'll run automatically with bin/dev or bin/jobs.",
          :green
        say_status :info,
          "Next steps: review docs/setup.md for the guided + manual install walkthrough and docs/troubleshooting.md for common fixes.",
          :green
      end

      private

      PROCFILE_JOBS_ENTRY = "jobs: bundle exec rake solid_queue:start"

      RECURRING_ENTRIES = {
        "source_monitor_schedule_fetches" => {
          "class" => "SourceMonitor::ScheduleFetchesJob",
          "args" => [ { "limit" => 100 } ],
          "schedule" => "every minute"
        },
        "source_monitor_schedule_scrapes" => {
          "command" => "SourceMonitor::Scraping::Scheduler.run(limit: 100)",
          "schedule" => "every 2 minutes"
        },
        "source_monitor_item_cleanup" => {
          "class" => "SourceMonitor::ItemCleanupJob",
          "schedule" => "at 2am every day"
        },
        "source_monitor_log_cleanup" => {
          "class" => "SourceMonitor::LogCleanupJob",
          "args" => [ { "fetch_logs_older_than_days" => 90, "scrape_logs_older_than_days" => 60 } ],
          "schedule" => "at 3am every day"
        }
      }.freeze

      def recurring_file_has_source_monitor_entries?(path)
        return false unless File.exist?(path)

        content = File.read(path)
        content.include?("source_monitor_schedule_fetches")
      end

      def merge_into_existing_recurring(destination, recurring_path)
        parsed = YAML.safe_load(File.read(destination), aliases: true) || {}
        default_key = parsed.key?("default") ? "default" : nil

        if default_key
          parsed["default"] = (parsed["default"] || {}).merge(RECURRING_ENTRIES)
        else
          parsed.merge!(RECURRING_ENTRIES)
        end

        write_recurring_yaml(destination, parsed, has_environments: parsed.key?("development"))
        say_status :append, recurring_path, :green
      end

      def create_recurring_file(destination, recurring_path)
        FileUtils.mkdir_p(File.dirname(destination))
        yaml_content = build_fresh_recurring_yaml
        File.write(destination, yaml_content)
        say_status :create, recurring_path, :green
      end

      def build_fresh_recurring_yaml
        entries_yaml = format_entries_yaml(RECURRING_ENTRIES)

        "default: &default\n#{entries_yaml}\n" \
          "development:\n  <<: *default\n\n" \
          "test:\n  <<: *default\n\n" \
          "production:\n  <<: *default\n"
      end

      def write_recurring_yaml(destination, parsed, has_environments: false)
        if has_environments
          default_entries = parsed["default"] || {}
          entries_yaml = format_entries_yaml(default_entries)
          envs = %w[development test production].select { |e| parsed.key?(e) }
          env_sections = envs.map { |e| "#{e}:\n  <<: *default" }.join("\n\n")

          content = "default: &default\n#{entries_yaml}"
          content += "\n#{env_sections}\n" unless envs.empty?
          File.write(destination, content)
        else
          File.write(destination, YAML.dump(parsed))
        end
      end

      def format_entries_yaml(entries)
        entries.map { |key, value|
          entry = YAML.dump({ key => value }).delete_prefix("---\n")
          entry.gsub(/^/, "  ")
        }.join("\n")
      end

      def engine_already_mounted?(mount_path)
        routes_path = File.join(destination_root, "config/routes.rb")
        return false unless File.exist?(routes_path)

        routes_content = File.read(routes_path)
        routes_content.include?("mount SourceMonitor::Engine, at: \"#{mount_path}\"") ||
          routes_content.include?("mount SourceMonitor::Engine")
      end

      def normalized_mount_path
        raw_path = options.key?(:mount_path) ? options[:mount_path] : "/source_monitor"
        path = (raw_path && !raw_path.strip.empty?) ? raw_path.strip : "/source_monitor"
        path.start_with?("/") ? path : "/#{path}"
      end
    end
  end
end
