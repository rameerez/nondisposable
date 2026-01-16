# frozen_string_literal: true

require "test_helper"

class IntegrationTest < NondisposableTestCase
  # =========================================================================
  # Full Workflow Integration Tests
  # =========================================================================

  def test_complete_workflow_from_update_to_validation
    # 1. Configure the gem
    Nondisposable.configure do |c|
      c.error_message = "Disposable emails are not allowed"
      c.additional_domains = ["custom-disposable.com"]
      c.excluded_domains = ["allowed-disposable.com"]
    end

    # 2. Simulate domain list update
    stub_domain_list("tempmail.com\ntrashmail.net\nallowed-disposable.com\n")
    result = Nondisposable::DomainListUpdater.update
    assert result

    # 3. Verify domains are in database
    assert Nondisposable::DisposableDomain.exists?(name: "tempmail.com")
    assert Nondisposable::DisposableDomain.exists?(name: "trashmail.net")
    refute Nondisposable::DisposableDomain.exists?(name: "allowed-disposable.com")

    # 4. Test validation with various emails
    user_good = User.new(email: "user@gmail.com")
    assert user_good.valid?

    user_disposable = User.new(email: "user@tempmail.com")
    refute user_disposable.valid?
    assert_includes user_disposable.errors[:email], "Disposable emails are not allowed"

    user_custom = User.new(email: "user@custom-disposable.com")
    refute user_custom.valid?

    user_excluded = User.new(email: "user@allowed-disposable.com")
    assert user_excluded.valid?
  end

  def test_direct_api_usage
    setup_disposable_domain!("bad.com")

    assert Nondisposable.disposable?("user@bad.com")
    refute Nondisposable.disposable?("user@good.com")
  end

  def test_model_validation_integration
    setup_disposable_domain!("spam.io")

    # Create user with valid email
    user1 = User.new(email: "valid@example.com")
    assert user1.valid?

    # Create user with disposable email
    user2 = User.new(email: "test@spam.io")
    refute user2.valid?

    # Check the model validation works correctly
    assert user2.errors[:email].any?
  end

  # =========================================================================
  # Multiple Model Integration Tests
  # =========================================================================

  def test_validation_works_across_multiple_models
    setup_disposable_domain!("throwaway.email")

    user = User.new(email: "test@throwaway.email")
    refute user.valid?

    contact = Contact.new(contact_email: "test@throwaway.email")
    refute contact.valid?

    subscriber = Subscriber.new(email: "test@throwaway.email")
    refute subscriber.valid?
  end

  def test_different_error_messages_per_model
    setup_disposable_domain!("temp.com")

    user = User.new(email: "x@temp.com")
    user.valid?
    assert_includes user.errors[:email], "provider is not allowed"

    subscriber = Subscriber.new(email: "x@temp.com")
    subscriber.valid?
    assert_includes subscriber.errors[:email], "is a throwaway address"
  end

  # =========================================================================
  # Configuration Integration Tests
  # =========================================================================

  def test_configuration_changes_affect_validation_immediately
    user1 = User.new(email: "user@custom.com")
    assert user1.valid?

    Nondisposable.configuration.additional_domains = ["custom.com"]

    user2 = User.new(email: "user@custom.com")
    refute user2.valid?

    Nondisposable.configuration.additional_domains = []

    user3 = User.new(email: "user@custom.com")
    assert user3.valid?
  end

  def test_excluded_domains_override_database
    setup_disposable_domain!("temp.com")

    user1 = User.new(email: "user@temp.com")
    refute user1.valid?

    Nondisposable.configuration.excluded_domains = ["temp.com"]

    user2 = User.new(email: "user@temp.com")
    assert user2.valid?
  end

  # =========================================================================
  # Domain List Update Integration Tests
  # =========================================================================

  def test_domain_list_updates_affect_validation
    user1 = User.new(email: "user@newdomain.com")
    assert user1.valid?

    stub_domain_list("newdomain.com\n")
    Nondisposable::DomainListUpdater.update

    user2 = User.new(email: "user@newdomain.com")
    refute user2.valid?
  end

  def test_domain_list_replacement_works
    stub_domain_list("first.com\n")
    Nondisposable::DomainListUpdater.update

    user1 = User.new(email: "user@first.com")
    refute user1.valid?

    stub_domain_list("second.com\n")
    Nondisposable::DomainListUpdater.update

    user2 = User.new(email: "user@first.com")
    assert user2.valid?

    user3 = User.new(email: "user@second.com")
    refute user3.valid?
  end

  # =========================================================================
  # Edge Cases Integration Tests
  # =========================================================================

  def test_international_email_validation
    setup_disposable_domain!("xn--nxasmq5b.com")

    user = User.new(email: "user@xn--nxasmq5b.com")
    refute user.valid?
  end

  def test_email_with_plus_addressing
    setup_disposable_domain!("tempmail.com")

    user = User.new(email: "user+tag@tempmail.com")
    refute user.valid?
  end

  def test_subdomain_handling
    setup_disposable_domain!("mail.tempmail.com")

    user1 = User.new(email: "user@mail.tempmail.com")
    refute user1.valid?

    user2 = User.new(email: "user@tempmail.com")
    assert user2.valid?
  end

  def test_very_long_email_validation
    long_domain = "a" * 200 + ".com"
    setup_disposable_domain!(long_domain)
    long_email = "user@#{long_domain}"

    user = User.new(email: long_email)
    refute user.valid?
  end

  # =========================================================================
  # Error Handling Integration Tests
  # =========================================================================

  def test_validation_continues_working_after_network_error
    # First, set up some domains
    stub_domain_list("existing.com\n")
    Nondisposable::DomainListUpdater.update

    # Simulate network error on subsequent update
    stub_request(:get, /disposable-email-domains/).to_raise(SocketError.new("no network"))
    Nondisposable::DomainListUpdater.update

    # Validation should still work with existing data
    user = User.new(email: "user@existing.com")
    refute user.valid?
  end

  # =========================================================================
  # Performance Smoke Tests
  # =========================================================================

  def test_validation_performance_with_many_domains
    # Set up a large number of domains
    domains = (1..1000).map { |i| "domain#{i}.com" }.join("\n")
    stub_domain_list(domains)
    Nondisposable::DomainListUpdater.update

    # Validation should still be fast
    start_time = Time.now
    100.times do
      User.new(email: "user@domain500.com").valid?
    end
    elapsed = Time.now - start_time

    # 100 validations should complete in under 1 second
    assert elapsed < 1.0, "Validation too slow: #{elapsed}s for 100 validations"
  end

  # =========================================================================
  # Concurrent Access Smoke Tests
  # =========================================================================

  def test_concurrent_validation_does_not_crash
    setup_disposable_domain!("concurrent.com")

    threads = 10.times.map do
      Thread.new do
        10.times do
          User.new(email: "user@concurrent.com").valid?
          User.new(email: "user@safe.com").valid?
        end
      end
    end

    threads.each(&:join)
    # If we get here without exceptions, the test passes
    assert true
  end
end
