# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in source_monitor.gemspec.
gemspec

gem "puma"

gem "pg"

gem "propshaft"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

group :development, :test do
  gem "brakeman", require: false
end

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"

group :test do
  gem "simplecov", require: false
  gem "test-prof", require: false
  gem "stackprof", require: false
  gem "capybara"
  gem "webmock"
  gem "vcr"
  gem "selenium-webdriver"
end
