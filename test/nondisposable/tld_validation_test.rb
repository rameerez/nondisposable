# frozen_string_literal: true

require "test_helper"

# The validator's side of TLD + lookalike checking: what a host actually sees
# when it flips `config.check_tld` on a model that already validates
# `nondisposable: true`.
class NondisposableTldValidationTest < NondisposableTestCase
  # =========================================================================
  # Off by default — the upgrade must be silent
  # =========================================================================

  def test_does_nothing_until_it_is_turned_on
    # Somebody upgrading the gem must not wake up to rejected signups. Both new
    # checks are opt-in, and this test is the contract.
    assert User.new(email: "example@gmail.con").valid?
    assert User.new(email: "someone@gmial.com").valid?
  end

  # =========================================================================
  # check_tld
  # =========================================================================

  def test_rejects_an_address_whose_tld_does_not_exist
    Nondisposable.configure { |c| c.check_tld = true }
    user = User.new(email: "someone@example.con")

    refute user.valid?
    assert_includes user.errors[:email], "doesn't look like a real email address"
  end

  def test_rejects_a_domain_with_no_tld_at_all
    Nondisposable.configure { |c| c.check_tld = true }

    refute User.new(email: "example@gmailmcom").valid?
  end

  def test_still_accepts_every_real_tld
    Nondisposable.configure { |c| c.check_tld = true }

    %w[gmail.com empresa.es startup.io shop.app bbc.co.uk x.xn--fiqs8s].each do |domain|
      assert User.new(email: "someone@#{domain}").valid?, "#{domain} should be accepted"
    end
  end

  def test_leaves_ip_literal_addresses_alone
    Nondisposable.configure { |c| c.check_tld = true }

    assert User.new(email: "someone@192.168.0.1").valid?
  end

  def test_a_custom_message_replaces_the_default
    Nondisposable.configure do |c|
      c.check_tld = true
      c.invalid_tld_error_message = "no parece un email real"
    end
    user = User.new(email: "someone@example.con")

    refute user.valid?
    assert_includes user.errors[:email], "no parece un email real"
  end

  # =========================================================================
  # blocked_tlds / allowed_tlds
  # =========================================================================

  def test_blocks_a_real_tld_the_host_does_not_want
    Nondisposable.configure do |c|
      c.check_tld = true
      c.blocked_tlds = %w[tk ml ga cf gq]
    end
    user = User.new(email: "someone@example.tk")

    refute user.valid?
    assert_includes user.errors[:email], "domain ending is not allowed"
  end

  def test_allowlist_mode_refuses_everything_else
    Nondisposable.configure do |c|
      c.check_tld = true
      c.allowed_tlds = %w[es]
    end

    assert User.new(email: "someone@empresa.es").valid?
    refute User.new(email: "someone@gmail.com").valid?
  end

  def test_blocked_tlds_do_nothing_while_check_tld_is_off
    # One switch, one behaviour: a host that never turned the TLD check on does
    # not get TLD rejections through a side door.
    Nondisposable.configure { |c| c.blocked_tlds = %w[tk] }

    assert User.new(email: "someone@example.tk").valid?
  end

  # =========================================================================
  # The suggestion phrases the rejection whenever we have one
  # =========================================================================

  def test_an_invalid_tld_we_can_correct_says_what_they_meant
    # "Doesn't look like a real email address" is true but useless; the same
    # verdict with the fix attached is what the user needs. So a nameable
    # correction always outranks the generic message.
    Nondisposable.configure { |c| c.check_tld = true }
    user = User.new(email: "example@gmail.con")

    refute user.valid?
    assert_includes user.errors[:email], "looks like a typo. Did you mean example@gmail.com?"
  end

  def test_an_invalid_tld_we_cannot_correct_falls_back_to_the_generic_message
    Nondisposable.configure { |c| c.check_tld = true }
    user = User.new(email: "someone@totally-unknown-domain.con")

    refute user.valid?
    assert_includes user.errors[:email], "doesn't look like a real email address"
  end

  def test_only_one_error_however_many_checks_fire
    # Stacking "provider is not allowed" under "did you mean gmail.com?" helps
    # nobody. At most one message, always the most useful one available.
    Nondisposable.configure { |c| c.check_tld = true }
    user = User.new(email: "example@gmail.con")

    refute user.valid?
    assert_equal 1, user.errors[:email].size
  end

  # =========================================================================
  # reject_lookalike_domains
  # =========================================================================

  def test_lookalikes_pass_until_rejection_is_switched_on
    # A suggestion is a guess about intent. Acting on a guess is a separate,
    # deliberate decision from acting on "this TLD does not exist".
    Nondisposable.configure { |c| c.check_tld = true }

    assert User.new(email: "someone@gmail.co").valid?
  end

  def test_rejects_lookalikes_when_asked_naming_the_correction
    Nondisposable.configure { |c| c.reject_lookalike_domains = true }
    user = User.new(email: "someone@gmail.co")

    refute user.valid?
    assert_includes user.errors[:email], "looks like a typo. Did you mean someone@gmail.com?"
  end

  def test_rejecting_lookalikes_never_touches_a_real_provider
    Nondisposable.configure { |c| c.reject_lookalike_domains = true }

    %w[gmail.com mail.com hotmail.es carhey.com bbc.co.uk].each do |domain|
      assert User.new(email: "someone@#{domain}").valid?, "#{domain} must not be rejected"
    end
  end

  def test_custom_lookalike_message_keeps_the_suggestion
    Nondisposable.configure do |c|
      c.reject_lookalike_domains = true
      c.lookalike_error_message = "¿Quisiste decir %{suggestion}?"
    end
    user = User.new(email: "someone@gmial.com")

    refute user.valid?
    assert_includes user.errors[:email], "¿Quisiste decir someone@gmail.com?"
  end

  # =========================================================================
  # Interaction with the disposable check
  # =========================================================================

  def test_the_disposable_check_still_wins_when_both_apply
    # A throwaway address is what this gem is for, and "provider is not allowed"
    # is the more accurate verdict — a correct spelling would not help.
    setup_disposable_domain!("tempmail.com")
    Nondisposable.configure { |c| c.check_tld = true }
    user = User.new(email: "someone@tempmail.com")

    refute user.valid?
    assert_includes user.errors[:email], "provider is not allowed"
    assert_equal 1, user.errors[:email].size
  end

  def test_blank_and_malformed_values_are_still_skipped
    Nondisposable.configure { |c| c.check_tld = true }

    assert OptionalEmailUser.new(email: "").valid?
    assert OptionalEmailUser.new(email: nil).valid?
    # No @ at all: a format concern, and not this validator's argument.
    assert User.new(email: "invalid-email").valid?
  end
end
