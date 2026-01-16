# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/nondisposable/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Nondisposable::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup :prepare_destination

  # =========================================================================
  # Basic Generator Tests
  # =========================================================================

  def test_generator_runs_without_errors
    assert_nothing_raised do
      run_generator
    end
  end

  def test_creates_migration_file
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb"
  end

  def test_migration_contains_table_creation
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "create_table :nondisposable_disposable_domains"
    end
  end

  def test_migration_has_name_column
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "t.string :name"
    end
  end

  def test_migration_has_null_false_constraint
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "null: false"
    end
  end

  def test_migration_has_unique_index
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "unique: true"
    end
  end

  def test_migration_has_timestamps
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      assert_includes content, "t.timestamps"
    end
  end

  # =========================================================================
  # Initializer Tests
  # =========================================================================

  def test_creates_initializer_file
    run_generator

    assert_file "config/initializers/nondisposable.rb"
  end

  def test_initializer_contains_configure_block
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "Nondisposable.configure"
    end
  end

  def test_initializer_documents_error_message_option
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "error_message"
    end
  end

  def test_initializer_documents_additional_domains_option
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "additional_domains"
    end
  end

  def test_initializer_documents_excluded_domains_option
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      assert_includes content, "excluded_domains"
    end
  end

  def test_initializer_options_are_commented_out
    run_generator

    assert_file "config/initializers/nondisposable.rb" do |content|
      # Verify options are commented (configuration examples)
      assert_includes content, "#"
    end
  end

  # =========================================================================
  # Job File Tests
  # =========================================================================

  def test_creates_job_file
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb"
  end

  def test_job_file_has_correct_class_name
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "class DisposableEmailDomainListUpdateJob"
    end
  end

  def test_job_inherits_from_application_job
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "< ApplicationJob"
    end
  end

  def test_job_has_queue_configuration
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "queue_as :default"
    end
  end

  def test_job_calls_domain_list_updater
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "Nondisposable::DomainListUpdater.update"
    end
  end

  def test_job_has_perform_method
    run_generator

    assert_file "app/jobs/disposable_email_domain_list_update_job.rb" do |content|
      assert_includes content, "def perform"
    end
  end

  # =========================================================================
  # All Files Created Together
  # =========================================================================

  def test_creates_all_three_files
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb"
    assert_file "config/initializers/nondisposable.rb"
    assert_file "app/jobs/disposable_email_domain_list_update_job.rb"
  end

  # =========================================================================
  # Migration Versioning Tests
  # =========================================================================

  def test_migration_includes_version_placeholder
    run_generator

    assert_migration "db/migrate/create_nondisposable_disposable_domains.rb" do |content|
      # Migration should have a version like [7.0], [7.1], [7.2], or [8.0]
      assert_match(/ActiveRecord::Migration\[\d+\.\d+\]/, content)
    end
  end

  # =========================================================================
  # Generator Class Tests
  # =========================================================================

  def test_generator_has_correct_source_root
    # Source root should end with the templates directory
    source_root = Nondisposable::Generators::InstallGenerator.source_root
    assert source_root.end_with?("lib/generators/nondisposable/templates")
    assert File.directory?(source_root)
  end

  def test_generator_responds_to_next_migration_number
    assert_respond_to Nondisposable::Generators::InstallGenerator, :next_migration_number
  end

  def test_generator_includes_active_record_migration
    assert Nondisposable::Generators::InstallGenerator.included_modules.include?(ActiveRecord::Generators::Migration)
  end
end
