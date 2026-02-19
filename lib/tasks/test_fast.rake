# frozen_string_literal: true

namespace :test do
  desc "Run tests excluding slow integration and system tests"
  task fast: :environment do
    $stdout.puts "Running tests excluding integration/ and system/ directories..."
    test_files = Dir["test/**/*_test.rb"]
      .reject { |f| f.start_with?("test/integration/", "test/system/") }
    system("bin/rails", "test", *test_files, exception: true)
  end
end
