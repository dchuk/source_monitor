# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "source_monitor/setup/skills_installer"

module SourceMonitor
  module Setup
    class SkillsInstallerTest < ActiveSupport::TestCase
      test "install defaults to consumer group" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            create_fake_skill(gem_root, "sm-dashboard-widget", "# consumer")
            create_fake_skill(gem_root, "sm-host-setup", "# consumer")
            create_fake_skill(gem_root, "sm-domain-model", "# contributor")

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir)

            assert_includes result[:installed], "sm-dashboard-widget"
            assert_includes result[:installed], "sm-host-setup"
            refute_includes result[:installed], "sm-domain-model"
            refute File.exist?(File.join(target_dir, "sm-domain-model"))
          end
        end
      end

      test "install with group: :consumer only installs consumer skills" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            SkillsInstaller::CONSUMER_SKILLS.each { |name| create_fake_skill(gem_root, name, "# #{name}") }
            SkillsInstaller::CONTRIBUTOR_SKILLS.each { |name| create_fake_skill(gem_root, name, "# #{name}") }

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir, group: :consumer)

            assert_equal SkillsInstaller::CONSUMER_SKILLS.sort, result[:installed].sort
            SkillsInstaller::CONTRIBUTOR_SKILLS.each do |name|
              refute File.exist?(File.join(target_dir, name))
            end
          end
        end
      end

      test "install with group: :contributor only installs contributor skills" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            SkillsInstaller::CONSUMER_SKILLS.each { |name| create_fake_skill(gem_root, name, "# #{name}") }
            SkillsInstaller::CONTRIBUTOR_SKILLS.each { |name| create_fake_skill(gem_root, name, "# #{name}") }

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir, group: :contributor)

            assert_equal SkillsInstaller::CONTRIBUTOR_SKILLS.sort, result[:installed].sort
            SkillsInstaller::CONSUMER_SKILLS.each do |name|
              refute File.exist?(File.join(target_dir, name))
            end
          end
        end
      end

      test "install with group: :all installs both groups" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            all_skills = SkillsInstaller::CONSUMER_SKILLS + SkillsInstaller::CONTRIBUTOR_SKILLS
            all_skills.each { |name| create_fake_skill(gem_root, name, "# #{name}") }

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir, group: :all)

            assert_equal all_skills.sort, result[:installed].sort
          end
        end
      end

      test "install is idempotent and skips existing skills" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            create_fake_skill(gem_root, "sm-host-setup", "# sm-host-setup")

            installer = SkillsInstaller.new(gem_root: gem_root)

            first_result = installer.install(target_dir: target_dir)
            assert_includes first_result[:installed], "sm-host-setup"

            second_result = installer.install(target_dir: target_dir)
            assert_empty second_result[:installed]
            assert_includes second_result[:skipped], "sm-host-setup"
          end
        end
      end

      test "remove deletes sm-* directories from target" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            create_fake_skill(gem_root, "sm-host-setup", "# consumer")
            create_fake_skill(gem_root, "sm-domain-model", "# contributor")

            installer = SkillsInstaller.new(gem_root: gem_root)
            installer.install(target_dir: target_dir, group: :all)

            assert File.exist?(File.join(target_dir, "sm-host-setup"))
            assert File.exist?(File.join(target_dir, "sm-domain-model"))

            result = installer.remove(target_dir: target_dir)

            assert_includes result[:removed], "sm-host-setup"
            assert_includes result[:removed], "sm-domain-model"
            refute File.exist?(File.join(target_dir, "sm-host-setup"))
            refute File.exist?(File.join(target_dir, "sm-domain-model"))
          end
        end
      end

      test "install handles missing gem skills directory gracefully" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir)

            assert_empty result[:installed]
            assert_empty result[:skipped]
          end
        end
      end

      test "remove handles missing target directory gracefully" do
        Dir.mktmpdir do |gem_root|
          installer = SkillsInstaller.new(gem_root: gem_root)
          result = installer.remove(target_dir: "/tmp/nonexistent_#{SecureRandom.hex(8)}")

          assert_empty result[:removed]
        end
      end

      test "install does not copy non-sm skills" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            create_fake_skill(gem_root, "sm-host-setup", "# sm-host-setup")
            create_fake_skill(gem_root, "rails-controller", "# rails-controller")

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir)

            assert_includes result[:installed], "sm-host-setup"
            refute File.exist?(File.join(target_dir, "rails-controller"))
          end
        end
      end

      test "install creates target directory if it does not exist" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |base_dir|
            target_dir = File.join(base_dir, "nested", "skills")
            create_fake_skill(gem_root, "sm-host-setup", "# sm-host-setup")

            installer = SkillsInstaller.new(gem_root: gem_root)
            result = installer.install(target_dir: target_dir)

            assert_includes result[:installed], "sm-host-setup"
            assert File.directory?(target_dir)
          end
        end
      end

      test "install raises ArgumentError for unknown group" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |target_dir|
            create_fake_skill(gem_root, "sm-host-setup", "# test")

            installer = SkillsInstaller.new(gem_root: gem_root)
            assert_raises(ArgumentError) { installer.install(target_dir: target_dir, group: :unknown) }
          end
        end
      end

      private

      def create_fake_skill(gem_root, name, content)
        skill_dir = File.join(gem_root, ".claude", "skills", name)
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), content)
      end
    end
  end
end
