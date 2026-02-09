# frozen_string_literal: true

require_relative "lib/source_monitor/version"

Gem::Specification.new do |spec|
  spec.name        = "source_monitor"
  spec.version     = SourceMonitor::VERSION
  spec.authors     = [ "dchuk" ]
  spec.email       = [ "me@dchuk.com" ]
  spec.homepage    = "https://github.com/dchuk/source_monitor"
  spec.summary     = "SourceMonitor engine for ingesting, scraping, and monitoring RSS/Atom/JSON feeds"
  spec.description = "SourceMonitor is a mountable Rails 8 engine that ingests RSS, Atom, and JSON feeds, scrapes full article content, and surfaces Solid Queue powered dashboards for monitoring and remediation."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.4.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/dchuk/source_monitor/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/dchuk/source_monitor#readme"
  spec.metadata["bug_tracker_uri"] = "https://github.com/dchuk/source_monitor/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    tracked_files = `git ls-files -z`.split("\x0")
    tracked_files.reject do |file|
      file.start_with?(".ai/", ".github/", "coverage/", "node_modules/", "pkg/", "spec/", "test/", "tmp/", "vendor/", "examples/", "bin/")
    end
  end
  spec.files += [ "CHANGELOG.md" ].select { |path| File.exist?(File.join(__dir__, path)) }
  spec.files.uniq!

  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 8.0.3", "< 9.0"
  spec.add_dependency "cssbundling-rails", "~> 1.4"
  spec.add_dependency "jsbundling-rails", "~> 1.3"
  spec.add_dependency "turbo-rails", "~> 2.0"
  spec.add_dependency "feedjira", ">= 3.2", "< 5.0"
  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"
  spec.add_dependency "faraday-follow_redirects", "~> 0.4"
  spec.add_dependency "faraday-gzip", "~> 3.0"
  spec.add_dependency "nokolexbor", "~> 0.5"
  spec.add_dependency "ruby-readability", "~> 0.7"
  spec.add_dependency "solid_queue", ">= 0.3", "< 3.0"
  spec.add_dependency "solid_cable", ">= 3.0", "< 4.0"
  spec.add_dependency "ransack", "~> 4.2"
end
