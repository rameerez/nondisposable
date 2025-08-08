# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/nondisposable/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Nondisposable::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup :prepare_destination

  def test_creates_migration_initializer_and_job
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "create_table :nondisposable_disposable_domains"
    end

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "Nondisposable.configure"
    end

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "Nondisposable::DomainListUpdater.update"
    end
  end
end