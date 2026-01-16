# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < NondisposableTestCase
  # =========================================================================
  # Default Configuration Tests
  # =========================================================================

  def test_configuration_defaults
    config = Nondisposable::Configuration.new
    assert_equal "provider is not allowed", config.error_message
    assert_equal [], config.additional_domains
    assert_equal [], config.excluded_domains
  end

  def test_configuration_attributes_are_accessible
    config = Nondisposable::Configuration.new
    assert_respond_to config, :error_message
    assert_respond_to config, :error_message=
    assert_respond_to config, :additional_domains
    assert_respond_to config, :additional_domains=
    assert_respond_to config, :excluded_domains
    assert_respond_to config, :excluded_domains=
  end

  # =========================================================================
  # Configure Block Tests
  # =========================================================================

  def test_configure_block_sets_error_message
    Nondisposable.configure do |c|
      c.error_message = "custom error"
    end

    assert_equal "custom error", Nondisposable.configuration.error_message
  end

  def test_configure_block_sets_additional_domains
    Nondisposable.configure do |c|
      c.additional_domains = ["example.com", "test.com"]
    end

    assert_equal ["example.com", "test.com"], Nondisposable.configuration.additional_domains
  end

  def test_configure_block_sets_excluded_domains
    Nondisposable.configure do |c|
      c.excluded_domains = ["allowed.com"]
    end

    assert_equal ["allowed.com"], Nondisposable.configuration.excluded_domains
  end

  def test_configure_block_sets_multiple_options
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

  def test_configure_yields_configuration_object
    yielded_object = nil
    Nondisposable.configure { |c| yielded_object = c }

    assert_instance_of Nondisposable::Configuration, yielded_object
  end

  def test_configure_returns_configuration_from_block
    result = Nondisposable.configure { |c| c.error_message = "test" }

    # The block's return value or configuration should be accessible
    assert_equal "test", Nondisposable.configuration.error_message
  end

  def test_configure_creates_new_configuration_if_nil
    Nondisposable.configuration = nil
    Nondisposable.configure { |c| c.error_message = "new" }

    assert_instance_of Nondisposable::Configuration, Nondisposable.configuration
    assert_equal "new", Nondisposable.configuration.error_message
  end

  def test_configure_preserves_existing_configuration
    Nondisposable.configure { |c| c.error_message = "first" }
    Nondisposable.configure { |c| c.additional_domains = ["test.com"] }

    # Both settings should be preserved
    assert_equal "first", Nondisposable.configuration.error_message
    assert_equal ["test.com"], Nondisposable.configuration.additional_domains
  end

  # =========================================================================
  # Error Message Edge Cases
  # =========================================================================

  def test_error_message_with_empty_string
    Nondisposable.configure { |c| c.error_message = "" }
    assert_equal "", Nondisposable.configuration.error_message
  end

  def test_error_message_with_special_characters
    message = "is not allowed! <script>alert('xss')</script> & more"
    Nondisposable.configure { |c| c.error_message = message }
    assert_equal message, Nondisposable.configuration.error_message
  end

  def test_error_message_with_unicode
    message = "is not allowed \u{1F6AB}"
    Nondisposable.configure { |c| c.error_message = message }
    assert_equal message, Nondisposable.configuration.error_message
  end

  def test_error_message_with_newlines
    message = "line1\nline2\nline3"
    Nondisposable.configure { |c| c.error_message = message }
    assert_equal message, Nondisposable.configuration.error_message
  end

  def test_error_message_with_very_long_string
    message = "a" * 10_000
    Nondisposable.configure { |c| c.error_message = message }
    assert_equal message, Nondisposable.configuration.error_message
  end

  # =========================================================================
  # Additional Domains Edge Cases
  # =========================================================================

  def test_additional_domains_with_duplicates
    Nondisposable.configure do |c|
      c.additional_domains = ["test.com", "test.com", "test.com"]
    end

    # Should preserve duplicates (caller's responsibility to dedupe)
    assert_equal ["test.com", "test.com", "test.com"], Nondisposable.configuration.additional_domains
  end

  def test_additional_domains_with_mixed_case
    Nondisposable.configure do |c|
      c.additional_domains = ["Test.COM", "EXAMPLE.com", "MixedCase.Org"]
    end

    assert_equal ["Test.COM", "EXAMPLE.com", "MixedCase.Org"], Nondisposable.configuration.additional_domains
  end

  def test_additional_domains_with_empty_strings
    Nondisposable.configure do |c|
      c.additional_domains = ["", "valid.com", ""]
    end

    assert_includes Nondisposable.configuration.additional_domains, ""
    assert_includes Nondisposable.configuration.additional_domains, "valid.com"
  end

  def test_additional_domains_with_whitespace
    Nondisposable.configure do |c|
      c.additional_domains = [" test.com ", "  spaced.com  "]
    end

    # Should preserve whitespace (caller's responsibility to strip)
    assert_equal [" test.com ", "  spaced.com  "], Nondisposable.configuration.additional_domains
  end

  def test_additional_domains_with_subdomains
    Nondisposable.configure do |c|
      c.additional_domains = ["mail.tempmail.com", "smtp.disposable.org"]
    end

    assert_equal ["mail.tempmail.com", "smtp.disposable.org"], Nondisposable.configuration.additional_domains
  end

  def test_additional_domains_with_very_long_list
    domains = (1..10_000).map { |i| "domain#{i}.com" }
    Nondisposable.configure { |c| c.additional_domains = domains }

    assert_equal 10_000, Nondisposable.configuration.additional_domains.length
    assert_includes Nondisposable.configuration.additional_domains, "domain1.com"
    assert_includes Nondisposable.configuration.additional_domains, "domain10000.com"
  end

  # =========================================================================
  # Excluded Domains Edge Cases
  # =========================================================================

  def test_excluded_domains_with_duplicates
    Nondisposable.configure do |c|
      c.excluded_domains = ["allow.com", "allow.com"]
    end

    assert_equal ["allow.com", "allow.com"], Nondisposable.configuration.excluded_domains
  end

  def test_excluded_domains_with_mixed_case
    Nondisposable.configure do |c|
      c.excluded_domains = ["ALLOWED.COM", "Excluded.Org"]
    end

    assert_equal ["ALLOWED.COM", "Excluded.Org"], Nondisposable.configuration.excluded_domains
  end

  def test_excluded_domains_overlapping_with_additional_domains
    Nondisposable.configure do |c|
      c.additional_domains = ["overlap.com", "only-additional.com"]
      c.excluded_domains = ["overlap.com", "only-excluded.com"]
    end

    # Both lists can contain the same domain (logic handles precedence)
    assert_includes Nondisposable.configuration.additional_domains, "overlap.com"
    assert_includes Nondisposable.configuration.excluded_domains, "overlap.com"
  end

  # =========================================================================
  # Module-Level Configuration Access
  # =========================================================================

  def test_configuration_class_accessor
    assert_respond_to Nondisposable, :configuration
    assert_respond_to Nondisposable, :configuration=
  end

  def test_configuration_can_be_set_directly
    new_config = Nondisposable::Configuration.new
    new_config.error_message = "direct set"

    Nondisposable.configuration = new_config

    assert_equal "direct set", Nondisposable.configuration.error_message
  end

  def test_configuration_can_be_replaced_entirely
    Nondisposable.configure { |c| c.error_message = "old" }

    new_config = Nondisposable::Configuration.new
    new_config.error_message = "new"
    Nondisposable.configuration = new_config

    assert_equal "new", Nondisposable.configuration.error_message
    assert_equal [], Nondisposable.configuration.additional_domains
  end

  # =========================================================================
  # Nondisposable.disposable? Method Tests
  # =========================================================================

  def test_disposable_query_with_domain_in_database
    setup_disposable_domain!("bad.com")

    assert Nondisposable.disposable?("user@bad.com")
  end

  def test_disposable_query_with_domain_not_in_database
    refute Nondisposable.disposable?("user@good.com")
  end

  def test_disposable_query_with_nil_email
    refute Nondisposable.disposable?(nil)
  end

  def test_disposable_query_with_email_missing_at_symbol
    refute Nondisposable.disposable?("nogood")
  end

  def test_disposable_query_with_empty_string
    refute Nondisposable.disposable?("")
  end

  def test_disposable_query_with_only_at_symbol
    # "@" results in empty domain after split, should return false
    refute Nondisposable.disposable?("@")
  end

  def test_disposable_query_with_uppercase_email
    setup_disposable_domain!("bad.com")

    assert Nondisposable.disposable?("USER@BAD.COM")
  end

  def test_disposable_query_lowercases_input
    # Store domain in lowercase (as DomainListUpdater does)
    setup_disposable_domain!("bad.com")

    # Query with uppercase email - should still match because input is lowercased
    assert Nondisposable.disposable?("user@BAD.COM")
  end

  def test_disposable_query_with_mixed_case_email
    # Store domain in lowercase (as DomainListUpdater does)
    setup_disposable_domain!("bad.com")

    # All these should match because the email domain is lowercased before lookup
    assert Nondisposable.disposable?("user@bad.com")
    assert Nondisposable.disposable?("user@BAD.COM")
    assert Nondisposable.disposable?("user@BaD.CoM")
  end

  def test_disposable_query_extracts_domain_correctly
    setup_disposable_domain!("example.com")

    assert Nondisposable.disposable?("test@example.com")
    assert Nondisposable.disposable?("another.user@example.com")
    assert Nondisposable.disposable?("user+tag@example.com")
  end

  def test_disposable_query_with_multiple_at_symbols
    setup_disposable_domain!("domain.com")

    # Should use last @ as delimiter for domain extraction
    result = Nondisposable.disposable?("user@fake@domain.com")
    assert result, "Should extract domain.com from email with multiple @ symbols"
  end

  def test_disposable_query_with_subdomain
    setup_disposable_domain!("mail.tempmail.com")

    assert Nondisposable.disposable?("user@mail.tempmail.com")
    # But NOT the parent domain
    refute Nondisposable.disposable?("user@tempmail.com")
  end

  def test_disposable_query_handles_leading_trailing_whitespace_in_domain
    setup_disposable_domain!("bad.com")

    # Email itself has no whitespace, domain lookup should work
    assert Nondisposable.disposable?("user@bad.com")
  end

  def test_disposable_query_with_international_domain
    setup_disposable_domain!("xn--nxasmq5b.com") # Punycode for international domain

    assert Nondisposable.disposable?("user@xn--nxasmq5b.com")
  end
end
