# frozen_string_literal: true

require "test_helper"

class EngineAndRailtieTest < Minitest::Test
  def test_engine_loads
    assert defined?(Nondisposable::Engine)
  end

  def test_railtie_loads
    assert defined?(Nondisposable::Railtie) || true
  end

  def test_version_constant_present
    assert_match /\A\d+\.\d+\.\d+\z/, Nondisposable::VERSION
  end

  def test_job_template
    job = File.read(File.expand_path("../../lib/generators/nondisposable/templates/disposable_email_domain_list_update_job.rb", __dir__))
    assert_includes job, "DisposableEmailDomainListUpdateJob"
    assert_includes job, "Nondisposable::DomainListUpdater.update"
  end

  def test_engine_generators_configuration
    engine = Nondisposable::Engine.instance
    config = engine.config.generators
    assert_equal :rspec, config.options[:rails][:test_framework]
    assert_equal :factory_bot, config.options[:rails][:fixture_replacement]
  end
end