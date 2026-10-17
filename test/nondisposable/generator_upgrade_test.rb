# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/nondisposable/install_generator"
require "generators/nondisposable/upgrade_generator"

# Hosts installed before 0.6.0 get the snapshots table from an ADDITIVE
# migration; fresh installs get it from the install generator.
class UpgradeGeneratorTest < Rails::Generators::TestCase
  tests Nondisposable::Generators::UpgradeGenerator
  destination File.expand_path("../../tmp/generator_upgrade_test", __dir__)

  setup :prepare_destination

  def test_creates_only_the_snapshots_migration
    run_generator

    assert_migration "db/migrate/create_nondisposable_source_snapshots.rb" do |content|
      assert_includes content, "create_table :nondisposable_source_snapshots"
      assert_includes content, "t.text :domains, limit: 16.megabytes"
      assert_match(/ActiveRecord::Migration\[\d+\.\d+\]/, content)
    end
    assert_no_migration "db/migrate/create_nondisposable_disposable_domains.rb"
    assert_no_file "config/initializers/nondisposable.rb"
  end

  def test_generated_migration_runs_and_rolls_back
    run_generator
    path = Dir[File.join(destination_root, "db/migrate/*_create_nondisposable_source_snapshots.rb")].first
    load path

    connection = ActiveRecord::Base.connection
    connection.drop_table(:nondisposable_source_snapshots, if_exists: true)
    ActiveRecord::Migration.suppress_messages { CreateNondisposableSourceSnapshots.migrate(:up) }

    assert connection.table_exists?(:nondisposable_source_snapshots)
    columns = connection.columns(:nondisposable_source_snapshots).map(&:name)
    %w[source url status fetched_at sha256 domain_count high_water_count domains error].each { |c| assert_includes columns, c }
    assert connection.index_exists?(:nondisposable_source_snapshots, [:source, :status, :fetched_at])

    ActiveRecord::Migration.suppress_messages { CreateNondisposableSourceSnapshots.migrate(:down) }
    refute connection.table_exists?(:nondisposable_source_snapshots)
  ensure
    ActiveRecord::Base.connection.drop_table(:nondisposable_source_snapshots, if_exists: true)
    Nondisposable::SourceSnapshot.reset_column_information
  end
end

class InstallGeneratorSnapshotsTest < Rails::Generators::TestCase
  tests Nondisposable::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_install_snapshots_test", __dir__)

  setup :prepare_destination

  def test_fresh_installs_get_both_tables
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb"
    assert_migration "db/migrate/create_nondisposable_source_snapshots.rb"
  end

  def test_initializer_documents_sources_and_relays
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "Nondisposable::Sources::RECOMMENDED"
      assert_includes content, "block_privacy_relays"
      assert_includes content, "corroboration_threshold"
    end
  end
end
