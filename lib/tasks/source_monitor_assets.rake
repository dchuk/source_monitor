# frozen_string_literal: true

require "source_monitor/assets/bundler"

namespace :source_monitor do
  namespace :assets do
    desc "Build SourceMonitor CSS and JS bundles"
    task build: :environment do
      SourceMonitor::Assets::Bundler.build!
    end

    desc "Verify required SourceMonitor asset bundles exist"
    task verify: :environment do
      SourceMonitor::Assets::Bundler.verify!
    end
  end
end

namespace :app do
  namespace :source_monitor do
    namespace :assets do
      task build: "source_monitor:assets:build"
      task verify: "source_monitor:assets:verify"
    end
  end
end

if defined?(Rake::Task) && Rake::Task.task_defined?("test")
  Rake::Task["test"].enhance([ "source_monitor:assets:verify" ])
end
