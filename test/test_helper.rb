# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
end

require "active_record"
require "rails"
require "webmock/minitest"
require "logger"

# Define a minimal Rails app for engine and ActiveRecord
class TestApp < Rails::Application
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :warn
  config.root = File.expand_path("..", __dir__)
  config.active_support.deprecation = :stderr
  config.secret_key_base = "a" * 64
end

# Initialize the application
Rails.application.initialize!

# Establish in-memory sqlite DB
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new($stdout)

# Load the gem code
require "nondisposable"

# Define a minimal ApplicationRecord and ApplicationJob for test app
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

require "active_job"
class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :inline

# Run the migration to create nondisposable_disposable_domains table using the generator template
require "rails/generators"
require "rails/generators/active_record"
require "rails/generators/test_case"
require "rails/generators/base"

# Build the migration class dynamically from the template logic
class CreateNondisposableDisposableDomains < ActiveRecord::Migration[7.0]
  def change
    create_table :nondisposable_disposable_domains do |t|
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end
  end
end

ActiveRecord::Schema.define(version: 1) do
  CreateNondisposableDisposableDomains.new.change
end

# Define a sample model to validate emails
class User < ApplicationRecord
  self.table_name = "users"
  validates :email, presence: true
  validates :email, nondisposable: true
end

ActiveRecord::Schema.define(version: 2) do
  create_table :users do |t|
    t.string :email
    t.timestamps
  end
end