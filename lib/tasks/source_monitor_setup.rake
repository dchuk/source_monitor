# frozen_string_literal: true

namespace :source_monitor do
  namespace :setup do
    desc "Verify host dependencies before running the guided SourceMonitor installer"
    task check: :environment do
      summary = SourceMonitor::Setup::DependencyChecker.new.call

      puts "SourceMonitor dependency check:" # rubocop:disable Rails/Output
      summary.results.each do |result|
        status = result.status.to_s.upcase
        current = result.current ? result.current.to_s : "missing"
        expected = result.expected || "n/a"
        puts "- #{result.name}: #{status} (current: #{current}, required: #{expected})" # rubocop:disable Rails/Output
      end

      if summary.errors?
        messages = summary.errors.map do |result|
          "#{result.name}: #{result.remediation}"
        end

        raise "SourceMonitor setup requirements failed. #{messages.join(' ')}"
      end
    end

    desc "Verify queue workers, Action Cable, and telemetry hooks"
    task verify: :environment do
      summary = SourceMonitor::Setup::Verification::Runner.new.call
      printer = SourceMonitor::Setup::Verification::Printer.new
      printer.print(summary)

      if ENV["SOURCE_MONITOR_SETUP_TELEMETRY"].present?
        SourceMonitor::Setup::Verification::TelemetryLogger.new.log(summary)
      end

      unless summary.ok?
        raise "SourceMonitor setup verification failed. See output above for remediation steps."
      end
    end
  end

  namespace :skills do
    desc "Install consumer Claude Code skills for using SourceMonitor"
    task :install do
      require "source_monitor/setup/skills_installer"

      install_skills(group: :consumer)
    end

    desc "Install contributor Claude Code skills for engine development"
    task :contributor do
      require "source_monitor/setup/skills_installer"

      install_skills(group: :contributor)
    end

    desc "Install all Claude Code skills (consumer + contributor)"
    task :all do
      require "source_monitor/setup/skills_installer"

      install_skills(group: :all)
    end

    desc "Remove Source Monitor Claude Code skills from host project"
    task :remove do
      require "source_monitor/setup/skills_installer"

      target_dir = File.join(Dir.pwd, ".claude", "skills")
      installer = SourceMonitor::Setup::SkillsInstaller.new

      result = installer.remove(target_dir:)

      if result[:removed].any?
        puts "Removed skills: #{result[:removed].join(', ')}" # rubocop:disable Rails/Output
      else
        puts "No sm-* skills found to remove." # rubocop:disable Rails/Output
      end
    end
  end
end

def install_skills(group:)
  target_dir = File.join(Dir.pwd, ".claude", "skills")
  installer = SourceMonitor::Setup::SkillsInstaller.new

  result = installer.install(target_dir:, group:)

  if result[:installed].any?
    puts "Installed skills: #{result[:installed].join(', ')}" # rubocop:disable Rails/Output
  end

  if result[:skipped].any?
    puts "Skipped (already installed): #{result[:skipped].join(', ')}" # rubocop:disable Rails/Output
  end

  if result[:installed].empty? && result[:skipped].empty?
    puts "No sm-* skills found in the source_monitor gem." # rubocop:disable Rails/Output
  end
end
