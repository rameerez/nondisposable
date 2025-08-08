# frozen_string_literal: true

require "test_helper"

class NondisposableValidatorTest < Minitest::Test
  def setup
    Nondisposable.configuration = Nondisposable::Configuration.new
    Nondisposable::DisposableDomain.delete_all
  end

  def test_allows_blank_values
    # Use a model without presence validation to isolate validator behavior
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      validates :email, nondisposable: true
    end
    user = klass.new(email: "")
    assert user.valid?, "Blank emails should be allowed by validator (presence handled elsewhere)"
  end

  def test_allows_invalid_format_without_at_symbol
    user = User.new(email: "invalid-email")
    # The validator returns if domain is nil (no '@'), so no error should be added here
    assert user.valid?, "Validator should skip invalid formats without adding errors"
  end

  def test_blocks_disposable_domain
    Nondisposable::DisposableDomain.create!(name: "trashmail.com")
    user = User.new(email: "foo@trashmail.com")
    refute user.valid?
    assert_includes user.errors[:email], Nondisposable.configuration.error_message
  end

  def test_blocks_additional_configured_domain_even_if_not_in_db
    Nondisposable.configuration.additional_domains = ["tempmail.com"]
    user = User.new(email: "bar@tempmail.com")
    refute user.valid?
    assert_includes user.errors[:email], Nondisposable.configuration.error_message
  end

  def test_allows_excluded_domains_even_if_in_db
    Nondisposable::DisposableDomain.create!(name: "filter.com")
    Nondisposable.configuration.excluded_domains = ["filter.com"]
    user = User.new(email: "ok@filter.com")
    assert user.valid?
  end

  def test_custom_error_message
    Nondisposable::DisposableDomain.create!(name: "spam.io")
    custom_message = "is a disposable email address, please use a permanent email address."
    user = Class.new(User) do
      validates :email, nondisposable: { message: "is a disposable email address, please use a permanent email address." }
    end.new(email: "u@spam.io")

    refute user.valid?
    assert_includes user.errors[:email], custom_message
  end

  def test_error_handling_logs_and_adds_fallback_error
    # Stub out DisposableDomain.disposable? to raise and ensure fallback error is added
    Nondisposable::DisposableDomain.stub(:disposable?, proc { raise "boom" }) do
      user = User.new(email: "x@y.com")
      refute user.valid?
      assert_includes user.errors[:email], "is an invalid email address, cannot check if it's disposable"
    end
  end

  def test_uppercase_email_is_handled
    Nondisposable::DisposableDomain.create!(name: "bad.com")
    user = User.new(email: "USER@BAD.COM")
    refute user.valid?
  end

  def test_helper_method_validates_nondisposable_email
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      extend ActiveModel::Validations::HelperMethods
      validates_nondisposable_email :email
    end
    Nondisposable::DisposableDomain.create!(name: "helper.com")
    user = klass.new(email: "x@helper.com")
    refute user.valid?
  end
end