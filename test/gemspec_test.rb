# frozen_string_literal: true

require "test_helper"

class GemspecTest < ActiveSupport::TestCase
  def setup
    @spec = Gem::Specification.load(File.expand_path("../source_monitor.gemspec", __dir__))
    assert_not_nil @spec, "Expected gemspec to load"
  end

  test "gemspec metadata is release ready" do
    assert_equal "SourceMonitor engine for ingesting, scraping, and monitoring RSS/Atom/JSON feeds", @spec.summary
    assert_includes @spec.description, "mountable Rails 8 engine"

      assert_equal "https://github.com/dchuk/source_monitor", @spec.metadata["source_code_uri"]
      assert_equal "https://github.com/dchuk/source_monitor/blob/main/CHANGELOG.md", @spec.metadata["changelog_uri"]
      assert_equal "https://github.com/dchuk/source_monitor#readme", @spec.metadata["documentation_uri"]
    assert_equal @spec.homepage, @spec.metadata["homepage_uri"]

    assert_nil @spec.metadata["allowed_push_host"], "allowed_push_host should not restrict RubyGems release"
    assert_equal "true", @spec.metadata["rubygems_mfa_required"], "rubygems_mfa_required metadata should be enforced"

    assert_equal Gem::Requirement.new(">= 3.4.0"), @spec.required_ruby_version
  end

  test "gem package excludes development artifacts" do
    disallowed_patterns = [
      %r{^test/},
      %r{^spec/},
      %r{^node_modules/},
      %r{^coverage/},
      %r{^tmp/},
      %r{^\.ai/},
      %r{^\.github/},
      %r{^examples/},
      %r{^vendor/},
      %r{^pkg/},
      %r{^bin/}
    ]

    disallowed_matches = @spec.files.select do |file|
      disallowed_patterns.any? { |pattern| file.match?(pattern) }
    end

    assert_empty disallowed_matches, "Expected gemspec to exclude development artifacts, found: #{disallowed_matches.inspect}"

    %w[MIT-LICENSE README.md CHANGELOG.md].each do |required_file|
      assert_includes @spec.files, required_file
    end
  end
end
