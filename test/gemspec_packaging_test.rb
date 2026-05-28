# frozen_string_literal: true

require "test_helper"

class GemspecPackagingTest < ActiveSupport::TestCase
  def setup
    @spec = Gem::Specification.load(File.expand_path("../source_monitor.gemspec", __dir__))
    assert_not_nil @spec, "Expected gemspec to load"
    @claude_files = @spec.files.select { |file| file.start_with?(".claude/") }
  end

  test "gem package excludes .claude internals" do
    disallowed_prefixes = [
      ".claude/agents",
      ".claude/hooks",
      ".claude/agent-memory",
      ".claude/settings.json",
      ".claude/commands"
    ]

    disallowed_matches = @spec.files.select do |file|
      disallowed_prefixes.any? { |prefix| file.start_with?(prefix) }
    end

    assert_empty disallowed_matches,
      "Expected gemspec to exclude .claude internals, found: #{disallowed_matches.inspect}"
  end

  test "gem package only ships sm-* skills from .claude" do
    non_sm_claude = @claude_files.reject { |file| file.start_with?(".claude/skills/sm-") }

    assert_empty non_sm_claude,
      "Expected only .claude/skills/sm-* files to ship, found: #{non_sm_claude.inspect}"
  end

  test "gem package includes sm-* skills from .claude" do
    assert_includes @spec.files, ".claude/skills/sm-host-setup/SKILL.md",
      "Expected sm-host-setup skill to be packaged"

    assert @claude_files.any? { |file| file.start_with?(".claude/skills/sm-") },
      "Expected at least one .claude/skills/sm-* file to be packaged"
  end

  test "gem package still ships core engine files" do
    assert @spec.files.any? { |file| file.start_with?("app/") }, "Expected app/ files to ship"
    assert @spec.files.any? { |file| file.start_with?("lib/") }, "Expected lib/ files to ship"
  end
end
