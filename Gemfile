# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in nondisposable.gemspec
gemspec

gem "rake", "~> 13.0"

group :test do
  gem "appraisal"
  gem "minitest", "~> 6.0"
  gem "minitest-mock"
  gem "minitest-reporters", "~> 1.6"
  gem "webmock", "~> 3.19"
  gem "sqlite3", "~> 2.1"
  gem "simplecov", require: false
  # Reads the lookalike corpus fixture; a bundled (not default) gem since Ruby 3.4.
  gem "csv"
end
