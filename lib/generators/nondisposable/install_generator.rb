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

      def setup_whenever
        if File.exist?('config/schedule.rb')
          append_to_file 'config/schedule.rb' do
            "\n# Update disposable email domains list daily\nevery 1.day, at: \"4:30 am\" do\n  rake \"nondisposable:update_disposable_domains\"\nend\n"
          end
        else
          create_file 'config/schedule.rb' do
            "# Use this file to easily define all of your cron jobs.\n#\n# Learn more: http://github.com/javan/whenever\n\n# Update disposable email domains list daily\nevery 1.day, at: \"4:30 am\" do\n  rake \"nondisposable:update_disposable_domains\"\nend\n"
          end
        end
      end

      def display_post_install_message
        say "\tThe `nondisposable` gem has been successfully installed!", :green
        say "\nTo complete the setup:"
        say "  1. Run 'rails db:migrate' to create the necessary tables."
        say "  2. Run 'rake nondisposable:update_disposable_domains' to populate the initial list of disposable domains."
        say "  3. Add 'validates :email, nondisposable: true' to your User model (or any model with an email field)."
        say "  4. Make sure you have a functional `whenever` gem install that can run cron jobs properly so the disposable emails list is updated daily."
        say "\nEnjoy your new `nondisposable` users!", :green
      end

    end
  end
end
