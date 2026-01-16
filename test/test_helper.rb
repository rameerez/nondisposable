# frozen_string_literal: true

require "bundler/setup"

# SimpleCov must be loaded BEFORE any application code
# Configuration is auto-loaded from .simplecov file
require "simplecov"

require "minitest/autorun"
require "minitest/mock"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

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

  # Disable asset pipeline for this test app (no assets in gem)
  config.assets = nil if config.respond_to?(:assets=)
end

# Initialize the application
Rails.application.initialize!

# Establish a shared-cache in-memory SQLite DB for thread safety.
# Using mode=memory&cache=shared allows multiple threads to share the same in-memory database.
# This is essential for tests that use threads (like concurrent validation tests).
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "file::memory:?cache=shared"
)
ActiveRecord::Base.logger = Logger.new($stdout)
ActiveRecord::Base.logger.level = Logger::WARN

# Load the gem code
require "nondisposable"

# Define a minimal ApplicationRecord and ApplicationJob for test app
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

require "active_job"
class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :inline

# Run the migration to create nondisposable_disposable_domains table
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

# Model with custom attribute name for email validation
class Contact < ApplicationRecord
  self.table_name = "contacts"
  validates :contact_email, nondisposable: true, allow_blank: true
end

# Model with custom error message
class Subscriber < ApplicationRecord
  self.table_name = "subscribers"
  validates :email, nondisposable: { message: "is a throwaway address" }
end

# Model without presence validation to test blank handling
class OptionalEmailUser < ApplicationRecord
  self.table_name = "users"
  validates :email, nondisposable: true, allow_blank: true
end

ActiveRecord::Schema.define(version: 2) do
  create_table :users do |t|
    t.string :email
    t.timestamps
  end

  create_table :contacts do |t|
    t.string :contact_email
    t.timestamps
  end

  create_table :subscribers do |t|
    t.string :email
    t.timestamps
  end
end

# Helper module for test setup/teardown
module NondisposableTestHelper
  def reset_configuration!
    Nondisposable.configuration = Nondisposable::Configuration.new
  end

  def clear_domains!
    Nondisposable::DisposableDomain.delete_all
  end

  def setup_disposable_domain!(name)
    Nondisposable::DisposableDomain.create!(name: name)
  end

  def stub_domain_list(body, status: 200)
    stub_request(:get, %r{raw\.githubusercontent\.com/.*/disposable_email_blocklist\.conf})
      .to_return(status: status, body: body)
  end

  # Ensures all required database tables exist.
  # This is necessary because generator tests (Rails::Generators::TestCase)
  # can affect the ActiveRecord connection state, causing in-memory SQLite
  # tables to become unavailable when tests run in certain orders.
  def ensure_database_schema!
    connection = ActiveRecord::Base.connection

    unless connection.table_exists?(:nondisposable_disposable_domains)
      connection.create_table :nondisposable_disposable_domains do |t|
        t.string :name, null: false, index: { unique: true }
        t.timestamps
      end
    end

    unless connection.table_exists?(:users)
      connection.create_table :users do |t|
        t.string :email
        t.timestamps
      end
    end

    unless connection.table_exists?(:contacts)
      connection.create_table :contacts do |t|
        t.string :contact_email
        t.timestamps
      end
    end

    unless connection.table_exists?(:subscribers)
      connection.create_table :subscribers do |t|
        t.string :email
        t.timestamps
      end
    end
  end
end

# Base test class that includes the helper
class NondisposableTestCase < Minitest::Test
  include NondisposableTestHelper

  def setup
    ensure_database_schema!
    reset_configuration!
    clear_domains!
    WebMock.reset!
  end

  def teardown
    WebMock.reset!
  end
end
