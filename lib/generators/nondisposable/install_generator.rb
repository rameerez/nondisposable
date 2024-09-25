# frozen_string_literal: true

require 'rails/generators/base'

module Nondisposable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def create_migration_file
        migration_template 'create_nondisposable_disposable_domains.rb', 'db/migrate/create_nondisposable_disposable_domains.rb'
      end

      def create_initializer
        template 'nondisposable.rb', 'config/initializers/nondisposable.rb'
      end
    end
  end
end
