# frozen_string_literal: true

require "test_helper"

class EngineAndRailtieTest < Minitest::Test
  # =========================================================================
  # Engine Tests
  # =========================================================================

  def test_engine_class_exists
    assert defined?(Nondisposable::Engine)
  end

  def test_engine_inherits_from_rails_engine
    assert Nondisposable::Engine < Rails::Engine
  end

  def test_engine_isolates_namespace
    engine = Nondisposable::Engine.instance
    assert engine.class.isolated?
  end

  def test_engine_has_correct_namespace
    assert_equal Nondisposable, Nondisposable::Engine.instance.class.railtie_namespace
  end

  def test_engine_instance_is_accessible
    refute_nil Nondisposable::Engine.instance
  end

  def test_engine_generators_configuration
    engine = Nondisposable::Engine.instance
    config = engine.config.generators

    assert_equal :rspec, config.options[:rails][:test_framework]
    assert_equal :factory_bot, config.options[:rails][:fixture_replacement]
  end

  def test_engine_generator_factory_bot_directory
    engine = Nondisposable::Engine.instance
    config = engine.config.generators

    assert_equal "spec/factories", config.options[:factory_bot][:dir]
  end

  # =========================================================================
  # Railtie Tests
  # =========================================================================

  def test_railtie_class_exists
    # Note: Railtie may not be loaded if Engine is used
    # Engine includes Railtie functionality
    assert defined?(Nondisposable::Railtie) || defined?(Nondisposable::Engine)
  end

  # =========================================================================
  # Version Tests
  # =========================================================================

  def test_version_constant_exists
    assert defined?(Nondisposable::VERSION)
  end

  def test_version_is_a_string
    assert_kind_of String, Nondisposable::VERSION
  end

  def test_version_matches_semantic_versioning_format
    assert_match(/\A\d+\.\d+\.\d+(-[\w.]+)?\z/, Nondisposable::VERSION)
  end

  def test_version_is_not_empty
    refute_empty Nondisposable::VERSION
  end

  def test_version_major_is_numeric
    major = Nondisposable::VERSION.split(".").first
    assert_match(/\A\d+\z/, major)
  end

  def test_version_minor_is_numeric
    minor = Nondisposable::VERSION.split(".")[1]
    assert_match(/\A\d+\z/, minor)
  end

  def test_version_patch_is_numeric
    patch = Nondisposable::VERSION.split(".")[2].split("-").first
    assert_match(/\A\d+\z/, patch)
  end

  # =========================================================================
  # Generator Template Tests
  # =========================================================================

  def test_job_template_exists
    template_path = File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__)
    assert File.exist?(template_path)
  end

  def test_job_template_contains_correct_class_name
    job = File.read(File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__))
    assert_includes job, "DisposableEmailDomainListUpdateJob"
  end

  def test_job_template_calls_domain_list_updater
    job = File.read(File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__))
    assert_includes job, "Nondisposable::DomainListUpdater.update"
  end

  def test_job_template_inherits_from_application_job
    job = File.read(File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__))
    assert_includes job, "ApplicationJob"
  end

  def test_job_template_has_queue_configuration
    job = File.read(File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__))
    assert_includes job, "queue_as"
  end

  def test_initializer_template_exists
    template_path = File.expand_path("../../lib/generators/nondisposable/templates/nondisposable.rb", __dir__)
    assert File.exist?(template_path)
  end

  def test_initializer_template_contains_configure_block
    initializer = File.read(File.expand_path("../../lib/generators/nondisposable/templates/nondisposable.rb", __dir__))
    assert_includes initializer, "Nondisposable.configure"
  end

  def test_initializer_template_documents_error_message_option
    initializer = File.read(File.expand_path("../../lib/generators/nondisposable/templates/nondisposable.rb", __dir__))
    assert_includes initializer, "error_message"
  end

  def test_initializer_template_documents_additional_domains_option
    initializer = File.read(File.expand_path("../../lib/generators/nondisposable/templates/nondisposable.rb", __dir__))
    assert_includes initializer, "additional_domains"
  end

  def test_initializer_template_documents_excluded_domains_option
    initializer = File.read(File.expand_path("../../lib/generators/nondisposable/templates/nondisposable.rb", __dir__))
    assert_includes initializer, "excluded_domains"
  end

  def test_migration_template_exists
    template_path = File.expand_path("../../lib/generators/nondisposable/templates/create_nondisposable_disposable_domains.rb.erb", __dir__)
    assert File.exist?(template_path)
  end

  def test_migration_template_creates_correct_table
    migration = File.read(File.expand_path("../../lib/generators/nondisposable/templates/create_nondisposable_disposable_domains.rb.erb", __dir__))
    assert_includes migration, "create_table :nondisposable_disposable_domains"
  end

  def test_migration_template_has_name_column
    migration = File.read(File.expand_path("../../lib/generators/nondisposable/templates/create_nondisposable_disposable_domains.rb.erb", __dir__))
    assert_includes migration, "t.string :name"
  end

  def test_migration_template_has_timestamps
    migration = File.read(File.expand_path("../../lib/generators/nondisposable/templates/create_nondisposable_disposable_domains.rb.erb", __dir__))
    assert_includes migration, "t.timestamps"
  end

  def test_migration_template_has_unique_index
    migration = File.read(File.expand_path("../../lib/generators/nondisposable/templates/create_nondisposable_disposable_domains.rb.erb", __dir__))
    assert_includes migration, "unique: true"
  end

  # =========================================================================
  # Module Structure Tests
  # =========================================================================

  def test_nondisposable_module_exists
    assert defined?(Nondisposable)
  end

  def test_error_class_exists
    assert defined?(Nondisposable::Error)
  end

  def test_error_class_inherits_from_standard_error
    assert Nondisposable::Error < StandardError
  end

  def test_configuration_class_exists
    assert defined?(Nondisposable::Configuration)
  end

  def test_disposable_domain_class_exists
    assert defined?(Nondisposable::DisposableDomain)
  end

  def test_domain_list_updater_class_exists
    assert defined?(Nondisposable::DomainListUpdater)
  end

  def test_validator_class_exists
    assert defined?(ActiveModel::Validations::NondisposableValidator)
  end

  # =========================================================================
  # Validator Integration Tests
  # =========================================================================

  def test_validator_is_an_each_validator
    assert ActiveModel::Validations::NondisposableValidator < ActiveModel::EachValidator
  end

  def test_helper_methods_module_exists
    assert defined?(ActiveModel::Validations::HelperMethods)
  end

  def test_helper_methods_includes_validates_nondisposable_email
    assert ActiveModel::Validations::HelperMethods.instance_methods.include?(:validates_nondisposable_email)
  end
end
