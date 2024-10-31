# frozen_string_literal: true

require 'rails/generators/base'
require 'rails/generators/active_record'

module Nondisposable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      def create_migration_file
        migration_template 'create_nondisposable_disposable_domains.rb.erb', File.join(db_migrate_path, "create_nondisposable_disposable_domains.rb")
      end

      def create_initializer
        template 'nondisposable.rb', 'config/initializers/nondisposable.rb'
      end

      def create_database_refresh_job
        template 'disposable_email_domain_list_update_job.rb', 'app/jobs/disposable_email_domain_list_update_job.rb'
      end

      def display_post_install_message
        say "\tThe `nondisposable` gem has been successfully installed!", :green
        say "\nTo complete the setup:"
        say "  1. Run 'rails db:migrate' to create the necessary tables."
        say "  2. Run 'Nondisposable::DomainListUpdater.update' to populate the initial list of disposable domains."
        say "  3. Add 'validates :email, nondisposable: true' to your User model (or any model with an email field)."
        say "  4. Configure your recurrent job according to the README, and make sure you have a functional queuing system (like solid_queue) that can run jobs properly so the disposable emails list is updated regularly."
        say "\nEnjoy your new `nondisposable` users!", :green
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::STRING.to_f}]"
      end

    end
  end
end
