# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class UpgradeCommandTest < ActiveSupport::TestCase
      test "returns up-to-date summary when version matches" do
        Dir.mktmpdir do |dir|
          version_file = File.join(dir, ".source_monitor_version")
          File.write(version_file, "0.4.0")

          migration_installer = Minitest::Mock.new
          install_generator = Minitest::Mock.new
          verifier = Minitest::Mock.new

          command = UpgradeCommand.new(
            migration_installer: migration_installer,
            install_generator: install_generator,
            verifier: verifier,
            version_file: version_file,
            current_version: "0.4.0"
          )

          summary = command.call

          assert summary.ok?
          assert_equal 1, summary.results.size
          assert_equal :upgrade, summary.results.first.key
          assert_match(/Already up to date/, summary.results.first.details)
          assert_match(/0\.4\.0/, summary.results.first.details)

          assert_mock migration_installer
          assert_mock install_generator
          assert_mock verifier
        end
      end

      test "runs upgrade flow when version differs" do
        Dir.mktmpdir do |dir|
          version_file = File.join(dir, ".source_monitor_version")
          File.write(version_file, "0.3.3")

          ok_summary = Verification::Summary.new([
            Verification::Result.new(key: :pending_migrations, name: "Pending Migrations", status: :ok, details: "ok")
          ])

          migration_installer = Minitest::Mock.new
          migration_installer.expect(:install, nil)
          install_generator = Minitest::Mock.new
          install_generator.expect(:run, nil)
          verifier = Minitest::Mock.new
          verifier.expect(:call, ok_summary)

          command = UpgradeCommand.new(
            migration_installer: migration_installer,
            install_generator: install_generator,
            verifier: verifier,
            version_file: version_file,
            current_version: "0.4.0"
          )

          summary = command.call

          assert summary.ok?
          assert_equal "0.4.0", File.read(version_file)

          assert_mock migration_installer
          assert_mock install_generator
          assert_mock verifier
        end
      end

      test "runs upgrade flow when version file missing" do
        Dir.mktmpdir do |dir|
          version_file = File.join(dir, ".source_monitor_version")

          ok_summary = Verification::Summary.new([
            Verification::Result.new(key: :pending_migrations, name: "Pending Migrations", status: :ok, details: "ok")
          ])

          migration_installer = Minitest::Mock.new
          migration_installer.expect(:install, nil)
          install_generator = Minitest::Mock.new
          install_generator.expect(:run, nil)
          verifier = Minitest::Mock.new
          verifier.expect(:call, ok_summary)

          command = UpgradeCommand.new(
            migration_installer: migration_installer,
            install_generator: install_generator,
            verifier: verifier,
            version_file: version_file,
            current_version: "0.4.0"
          )

          summary = command.call

          assert summary.ok?
          assert File.exist?(version_file)
          assert_equal "0.4.0", File.read(version_file)

          assert_mock migration_installer
          assert_mock install_generator
          assert_mock verifier
        end
      end

      test "does not write version marker when verification raises" do
        Dir.mktmpdir do |dir|
          version_file = File.join(dir, ".source_monitor_version")
          File.write(version_file, "0.3.3")

          migration_installer = Minitest::Mock.new
          migration_installer.expect(:install, nil)
          install_generator = Minitest::Mock.new
          install_generator.expect(:run, nil)

          exploding_verifier = -> { raise "verification exploded" }

          command = UpgradeCommand.new(
            migration_installer: migration_installer,
            install_generator: install_generator,
            verifier: exploding_verifier,
            version_file: version_file,
            current_version: "0.4.0"
          )

          assert_raises(RuntimeError, "verification exploded") do
            command.call
          end

          assert_equal "0.3.3", File.read(version_file)

          assert_mock migration_installer
          assert_mock install_generator
        end
      end

      test "version marker file is plain text with version string" do
        Dir.mktmpdir do |dir|
          version_file = File.join(dir, ".source_monitor_version")

          ok_summary = Verification::Summary.new([
            Verification::Result.new(key: :pending_migrations, name: "Pending Migrations", status: :ok, details: "ok")
          ])

          migration_installer = Minitest::Mock.new
          migration_installer.expect(:install, nil)
          install_generator = Minitest::Mock.new
          install_generator.expect(:run, nil)
          verifier = Minitest::Mock.new
          verifier.expect(:call, ok_summary)

          command = UpgradeCommand.new(
            migration_installer: migration_installer,
            install_generator: install_generator,
            verifier: verifier,
            version_file: version_file,
            current_version: "0.4.0"
          )

          command.call

          content = File.read(version_file)
          assert_equal "0.4.0", content
          assert_equal content, content.strip

          assert_mock migration_installer
          assert_mock install_generator
          assert_mock verifier
        end
      end
    end
  end
end
