# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    Nondisposable.configuration = Nondisposable::Configuration.new
    Nondisposable::DisposableDomain.delete_all
  end

  def test_configuration_defaults
    config = Nondisposable.configuration
    assert_equal "provider is not allowed", config.error_message
    assert_equal [], config.additional_domains
    assert_equal [], config.excluded_domains
  end

  def test_configure_block
    Nondisposable.configure do |c|
      c.error_message = "blocked"
      c.additional_domains = ["added.com"]
      c.excluded_domains = ["excluded.com"]
    end

    config = Nondisposable.configuration
    assert_equal "blocked", config.error_message
    assert_equal ["added.com"], config.additional_domains
    assert_equal ["excluded.com"], config.excluded_domains
  end

  def test_disposable_query_helper_method
    Nondisposable::DisposableDomain.create!(name: "bad.com")
    assert Nondisposable.disposable?("user@bad.com")
    refute Nondisposable.disposable?("user@good.com")
    refute Nondisposable.disposable?(nil)
    refute Nondisposable.disposable?("nogood")
  end
end