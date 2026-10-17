# frozen_string_literal: true

require 'rails/generators/base'
require 'rails/generators/active_record'

module Nondisposable
  module Generators
    # For apps installed before 0.6.0: adds the source snapshots table that
    # multi-source blocklists need. Purely additive — it touches no existing
    # table, and the app keeps working the old way until it is migrated.
    #
    #   rails generate nondisposable:upgrade
    #   rails db:migrate
    class UpgradeGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      def create_source_snapshots_migration
        migration_template 'create_nondisposable_source_snapshots.rb.erb',
                           File.join(db_migrate_path, 'create_nondisposable_source_snapshots.rb')
      end

      def display_post_upgrade_message
        say "\tAdded the nondisposable_source_snapshots migration.", :green
        say "\nNext:"
        say "  1. Run 'rails db:migrate'. Until you do, the gem keeps using the single default list, so deploying first is safe."
        say "  2. Optionally choose your sources in config/initializers/nondisposable.rb, e.g. config.sources = Nondisposable::Sources::RECOMMENDED"
        say "  3. Run 'Nondisposable::DomainListUpdater.update' (or wait for your scheduled job)."
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::STRING.to_f}]"
      end
    end
  end
end
