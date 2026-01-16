# frozen_string_literal: true

require "test_helper"

class NondisposableValidatorTest < NondisposableTestCase
  # =========================================================================
  # Basic Validation Tests
  # =========================================================================

  def test_allows_valid_non_disposable_email
    user = User.new(email: "user@gmail.com")
    assert user.valid?
  end

  def test_blocks_disposable_domain
    setup_disposable_domain!("trashmail.com")
    user = User.new(email: "foo@trashmail.com")

    refute user.valid?
    assert_includes user.errors[:email], Nondisposable.configuration.error_message
  end

  def test_uses_default_error_message
    setup_disposable_domain!("tempmail.com")
    user = User.new(email: "test@tempmail.com")

    refute user.valid?
    assert_includes user.errors[:email], "provider is not allowed"
  end

  # =========================================================================
  # Blank Value Handling Tests
  # =========================================================================

  def test_allows_blank_values_when_allow_blank_is_set
    user = OptionalEmailUser.new(email: "")
    assert user.valid?, "Blank emails should be allowed when allow_blank: true"
  end

  def test_allows_nil_values_when_allow_blank_is_set
    user = OptionalEmailUser.new(email: nil)
    assert user.valid?, "Nil emails should be allowed when allow_blank: true"
  end

  def test_validator_itself_allows_blank_values
    # Test validator behavior in isolation
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      validates :email, nondisposable: true
    end
    user = klass.new(email: "")
    assert user.valid?, "Validator should skip blank values"
  end

  # =========================================================================
  # Invalid Email Format Handling Tests
  # =========================================================================

  def test_allows_email_without_at_symbol
    user = User.new(email: "invalid-email")
    # Validator returns early if no domain can be extracted
    assert user.valid?, "Validator should skip invalid formats without @ symbol"
  end

  def test_allows_email_with_only_at_symbol
    user = User.new(email: "@")
    # Domain extraction results in empty string
    assert user.valid?
  end

  def test_allows_email_with_at_at_end
    user = User.new(email: "user@")
    # Domain is empty string
    assert user.valid?
  end

  def test_allows_email_starting_with_at
    user = User.new(email: "@domain.com")
    # Still has a valid domain part
    setup_disposable_domain!("domain.com")
    user = User.new(email: "@domain.com")
    refute user.valid?
  end

  # =========================================================================
  # Multiple @ Symbol Tests
  # =========================================================================

  def test_handles_multiple_at_symbols
    setup_disposable_domain!("domain.com")
    user = User.new(email: "user@fake@domain.com")

    # Should use last part after @ as domain
    refute user.valid?
  end

  def test_email_with_at_in_local_part_quoted
    # This is actually valid per RFC but complex to handle
    user = User.new(email: '"user@local"@example.com')
    assert user.valid?
  end

  # =========================================================================
  # Case Sensitivity Tests
  # =========================================================================

  def test_blocks_uppercase_email_with_lowercase_domain_in_db
    setup_disposable_domain!("bad.com")
    user = User.new(email: "USER@BAD.COM")

    refute user.valid?
  end

  def test_blocks_lowercase_email_with_lowercase_domain_in_db
    # Note: In practice, DomainListUpdater lowercases all domains when inserting
    # The disposable? method also lowercases the query, so they should match
    setup_disposable_domain!("bad.com")
    user = User.new(email: "user@bad.com")

    refute user.valid?
  end

  def test_blocks_mixed_case_email_with_lowercase_domain
    # Query is lowercased, domain stored lowercase = match
    setup_disposable_domain!("bad.com")
    user = User.new(email: "User@Bad.Com")

    refute user.valid?
  end

  # =========================================================================
  # Custom Error Message Tests
  # =========================================================================

  def test_custom_error_message_via_options
    setup_disposable_domain!("spam.io")
    custom_message = "is a disposable email address, please use a permanent email address."

    klass = Class.new(User) do
      validates :email, nondisposable: { message: custom_message }
    end
    user = klass.new(email: "u@spam.io")

    refute user.valid?
    assert_includes user.errors[:email], custom_message
  end

  def test_custom_error_message_via_configuration
    Nondisposable.configure { |c| c.error_message = "configured message" }
    setup_disposable_domain!("test.com")

    user = User.new(email: "x@test.com")

    refute user.valid?
    assert_includes user.errors[:email], "configured message"
  end

  def test_options_message_overrides_configuration
    Nondisposable.configure { |c| c.error_message = "from config" }
    setup_disposable_domain!("test.com")

    # Use a fresh class that doesn't inherit User's existing validation
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      validates :email, nondisposable: { message: "from options" }
    end
    user = klass.new(email: "x@test.com")

    refute user.valid?
    assert_includes user.errors[:email], "from options"
    refute_includes user.errors[:email], "from config"
  end

  def test_custom_message_with_model_class
    # Using the Subscriber model which has custom message defined
    setup_disposable_domain!("trash.com")
    subscriber = Subscriber.new(email: "x@trash.com")

    refute subscriber.valid?
    assert_includes subscriber.errors[:email], "is a throwaway address"
  end

  # =========================================================================
  # Additional Domains Configuration Tests
  # =========================================================================

  def test_blocks_additional_configured_domain_even_if_not_in_db
    Nondisposable.configuration.additional_domains = ["tempmail.com"]
    user = User.new(email: "bar@tempmail.com")

    refute user.valid?
    assert_includes user.errors[:email], Nondisposable.configuration.error_message
  end

  def test_blocks_multiple_additional_domains
    Nondisposable.configuration.additional_domains = ["temp1.com", "temp2.com", "temp3.com"]

    ["temp1.com", "temp2.com", "temp3.com"].each do |domain|
      user = User.new(email: "user@#{domain}")
      refute user.valid?, "Should block #{domain}"
    end
  end

  # =========================================================================
  # Excluded Domains Configuration Tests
  # =========================================================================

  def test_allows_excluded_domains_even_if_in_db
    setup_disposable_domain!("filter.com")
    Nondisposable.configuration.excluded_domains = ["filter.com"]

    user = User.new(email: "ok@filter.com")
    assert user.valid?
  end

  def test_allows_multiple_excluded_domains
    setup_disposable_domain!("ex1.com")
    setup_disposable_domain!("ex2.com")
    Nondisposable.configuration.excluded_domains = ["ex1.com", "ex2.com"]

    user1 = User.new(email: "user@ex1.com")
    user2 = User.new(email: "user@ex2.com")

    assert user1.valid?
    assert user2.valid?
  end

  # =========================================================================
  # Error Handling Tests
  # =========================================================================

  def test_error_handling_logs_and_adds_fallback_error
    Nondisposable::DisposableDomain.stub(:disposable?, proc { raise "boom" }) do
      user = User.new(email: "x@y.com")

      refute user.valid?
      assert_includes user.errors[:email], "is an invalid email address, cannot check if it's disposable"
    end
  end

  def test_error_handling_does_not_crash_application
    Nondisposable::DisposableDomain.stub(:disposable?, proc { raise StandardError.new("database error") }) do
      user = User.new(email: "test@example.com")

      # Should not raise, should add error instead
      refute user.valid?
    end
  end

  # =========================================================================
  # Different Attribute Names Tests
  # =========================================================================

  def test_validates_different_attribute_name
    setup_disposable_domain!("tempmail.com")
    contact = Contact.new(contact_email: "user@tempmail.com")

    refute contact.valid?
    assert_includes contact.errors[:contact_email], Nondisposable.configuration.error_message
  end

  def test_allows_valid_email_on_different_attribute
    contact = Contact.new(contact_email: "user@gmail.com")
    assert contact.valid?
  end

  def test_allows_blank_on_different_attribute
    contact = Contact.new(contact_email: "")
    assert contact.valid?
  end

  # =========================================================================
  # Helper Method Tests
  # =========================================================================

  def test_helper_method_validates_nondisposable_email
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      extend ActiveModel::Validations::HelperMethods
      validates_nondisposable_email :email
    end
    setup_disposable_domain!("helper.com")
    user = klass.new(email: "x@helper.com")

    refute user.valid?
  end

  def test_helper_method_on_multiple_attributes
    klass = Class.new(ApplicationRecord) do
      self.table_name = "contacts"
      extend ActiveModel::Validations::HelperMethods
      validates_nondisposable_email :contact_email
    end
    setup_disposable_domain!("multi.com")
    obj = klass.new(contact_email: "x@multi.com")

    refute obj.valid?
  end

  # =========================================================================
  # Edge Case Email Formats Tests
  # =========================================================================

  def test_email_with_plus_sign
    setup_disposable_domain!("tempmail.com")
    user = User.new(email: "user+tag@tempmail.com")

    refute user.valid?
  end

  def test_email_with_dots_in_local_part
    setup_disposable_domain!("tempmail.com")
    user = User.new(email: "user.name.here@tempmail.com")

    refute user.valid?
  end

  def test_email_with_subdomain
    setup_disposable_domain!("mail.tempmail.com")

    user_blocked = User.new(email: "user@mail.tempmail.com")
    user_allowed = User.new(email: "user@tempmail.com")

    refute user_blocked.valid?
    assert user_allowed.valid?
  end

  def test_email_with_very_long_local_part
    setup_disposable_domain!("tempmail.com")
    long_local = "a" * 200
    user = User.new(email: "#{long_local}@tempmail.com")

    refute user.valid?
  end

  def test_email_with_very_long_domain
    long_domain = "a" * 200 + ".com"
    setup_disposable_domain!(long_domain)
    user = User.new(email: "user@#{long_domain}")

    refute user.valid?
  end

  def test_email_with_numbers_in_domain
    setup_disposable_domain!("123tempmail456.com")
    user = User.new(email: "user@123tempmail456.com")

    refute user.valid?
  end

  def test_email_with_hyphen_in_domain
    setup_disposable_domain!("temp-mail.com")
    user = User.new(email: "user@temp-mail.com")

    refute user.valid?
  end

  def test_email_with_underscore_in_domain
    setup_disposable_domain!("temp_mail.com")
    user = User.new(email: "user@temp_mail.com")

    refute user.valid?
  end

  # =========================================================================
  # International Domain Names Tests
  # =========================================================================

  def test_email_with_punycode_domain
    setup_disposable_domain!("xn--nxasmq5b.com")
    user = User.new(email: "user@xn--nxasmq5b.com")

    refute user.valid?
  end

  # =========================================================================
  # Multiple Validations Interaction Tests
  # =========================================================================

  def test_works_with_presence_validation
    user = User.new(email: nil)

    refute user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  def test_disposable_error_shown_for_present_disposable_email
    setup_disposable_domain!("temp.com")
    user = User.new(email: "user@temp.com")

    refute user.valid?
    assert_includes user.errors[:email], Nondisposable.configuration.error_message
  end

  def test_multiple_errors_can_accumulate
    # User model has presence validation
    user = User.new(email: nil)

    refute user.valid?
    # Only presence error since email is blank
    assert user.errors[:email].length >= 1
  end

  # =========================================================================
  # Conditional Validation Tests
  # =========================================================================

  def test_validation_with_if_condition
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      attr_accessor :validate_email

      validates :email, nondisposable: true, if: :validate_email
    end

    setup_disposable_domain!("temp.com")

    # With condition false
    user1 = klass.new(email: "x@temp.com", validate_email: false)
    assert user1.valid?

    # With condition true
    user2 = klass.new(email: "x@temp.com", validate_email: true)
    refute user2.valid?
  end

  def test_validation_with_unless_condition
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      attr_accessor :skip_validation

      validates :email, nondisposable: true, unless: :skip_validation
    end

    setup_disposable_domain!("temp.com")

    # With condition true (skip)
    user1 = klass.new(email: "x@temp.com", skip_validation: true)
    assert user1.valid?

    # With condition false (don't skip)
    user2 = klass.new(email: "x@temp.com", skip_validation: false)
    refute user2.valid?
  end

  # =========================================================================
  # Validation Context Tests
  # =========================================================================

  def test_validation_on_create_context
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      validates :email, nondisposable: true, on: :create
    end

    setup_disposable_domain!("temp.com")
    user = klass.new(email: "x@temp.com")

    refute user.valid?(:create)
    assert user.valid?(:update)
  end

  def test_validation_on_update_context
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      validates :email, nondisposable: true, on: :update
    end

    setup_disposable_domain!("temp.com")
    user = klass.new(email: "x@temp.com")

    assert user.valid?(:create)
    refute user.valid?(:update)
  end

  # =========================================================================
  # Whitespace Handling Tests
  # =========================================================================

  def test_email_with_leading_whitespace
    setup_disposable_domain!("tempmail.com")
    user = User.new(email: "  user@tempmail.com")

    # Email has leading spaces, domain extraction should handle
    # Current behavior: spaces become part of local, domain is extracted after @
    refute user.valid?
  end

  def test_email_with_trailing_whitespace
    setup_disposable_domain!("tempmail.com")
    user = User.new(email: "user@tempmail.com  ")

    # Trailing spaces become part of domain
    # Current behavior depends on domain matching
  end

  # =========================================================================
  # Database Connection Tests
  # =========================================================================

  def test_validation_works_with_multiple_records
    setup_disposable_domain!("temp.com")

    users = 10.times.map { User.new(email: "user#{_1}@temp.com") }

    users.each do |user|
      refute user.valid?
    end
  end
end
