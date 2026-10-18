# frozen_string_literal: true

require "test_helper"

# What `reject_lookalike_domains` does since 0.5.0: hard-reject only what we
# KNOW is a typo, and make every other lookalike a question the user can
# answer. The tests named after real organisations are the reason this file
# exists — before 0.5.0 each of them was a person refused at signup.
class NondisposableLookalikeValidationTest < NondisposableTestCase
  def enable(mode = :confirmable, **extra)
    Nondisposable.configure do |c|
      c.reject_lookalike_domains = mode
      extra.each { |key, value| c.public_send("#{key}=", value) }
    end
  end

  def confirmed(email)
    ConfirmingUser.new(email: email, email_lookalike_confirmed: "1")
  end

  # =========================================================================
  # Off by default — unchanged
  # =========================================================================

  def test_off_by_default_nothing_is_flagged_not_even_a_known_typo
    assert_equal false, Nondisposable.configuration.reject_lookalike_domains
    assert User.new(email: "someone@gmial.com").valid?
    assert User.new(email: "someone@ge.com").valid?
  end

  # =========================================================================
  # The three kinds of row
  # =========================================================================

  def test_a_known_typo_is_refused_and_confirmation_cannot_override_it
    enable

    user = confirmed("someone@gmial.com")
    refute user.valid?
    assert_includes user.errors[:email], "looks like a typo. Did you mean someone@gmail.com?"
    # Not the confirmable kind: the form must not offer a checkbox here.
    refute user.errors.of_kind?(:email, :lookalike_domain)
  end

  def test_every_known_typo_is_refused_with_its_own_correction
    enable

    Nondisposable::KnownTypos.all.each do |typo, correction|
      user = confirmed("someone@#{typo}")
      refute user.valid?, "#{typo} is a reviewed typo and must be refused"
      assert_includes user.errors[:email], "looks like a typo. Did you mean someone@#{correction}?"
    end
  end

  def test_an_impossible_tld_is_refused_even_with_check_tld_off
    # `gmail.con` cannot receive the confirmation email, so "yes, this is my
    # address" has nothing to be right about.
    enable

    %w[gmail.con gmailmcom outlook.ed].each do |domain|
      user = confirmed("example@#{domain}")
      refute user.valid?, "#{domain} must stay a hard error"
      refute user.errors.of_kind?(:email, :lookalike_domain)
    end
  end

  def test_an_unreviewed_lookalike_is_a_question_not_a_wall
    enable
    user = ConfirmingUser.new(email: "someone@gnail.com")

    refute user.valid?
    assert user.errors.of_kind?(:email, :lookalike_domain)
    assert_includes user.errors[:email], "looks like a typo. Did you mean someone@gmail.com?"
    assert_equal "someone@gmail.com", user.errors.details[:email].first[:suggestion]

    assert confirmed("someone@gnail.com").valid?
  end

  def test_real_organisations_found_in_the_tranco_top_1m_can_always_get_through
    # Each of these was refused outright by `true` before 0.5.0.
    enable

    %w[ge.com ml.com mi.com se.com ea.com aa.com bol.com aon.com uol.com one.com
       hive.com life.com grail.com pmail.com web.dev yahoo.com.au].each do |domain|
      assert confirmed("someone@#{domain}").valid?, "#{domain} must pass once the user confirms it"
    end
  end

  def test_short_provider_names_no_longer_drag_in_their_neighbours
    # The ranker stops suggesting me.com to ge.com in the first place, so most
    # of these users never even see the question.
    enable

    %w[ge.com ml.com mi.com se.com ea.com aa.com bol.com aon.com one.com hive.com grail.com pmail.com].each do |domain|
      assert ConfirmingUser.new(email: "someone@#{domain}").valid?, "#{domain} should not even be asked"
    end
  end

  def test_valid_alternative_suffixes_are_never_hard_rejected
    # yahoo.com.au is Yahoo Australia and web.dev is Google's; both sit one
    # edit from a provider and both are real. At most they are a question.
    enable

    %w[yahoo.com.au web.dev yahoo.com.my].each do |domain|
      refute Nondisposable::KnownTypos.include?(domain)
      assert confirmed("someone@#{domain}").valid?
    end
  end

  # =========================================================================
  # Modes
  # =========================================================================

  def test_true_means_confirmable_for_backward_compatibility
    enable(true)

    assert confirmed("someone@gnail.com").valid?
    refute ConfirmingUser.new(email: "someone@gnail.com").valid?
    refute confirmed("someone@gmial.com").valid?
  end

  def test_string_modes_from_yaml_or_env_are_understood
    enable("confirmable")
    assert_equal :confirmable, Nondisposable.configuration.reject_lookalike_domains

    enable("false")
    assert_equal false, Nondisposable.configuration.reject_lookalike_domains

    enable(nil)
    assert_equal false, Nondisposable.configuration.reject_lookalike_domains
  end

  def test_an_unknown_mode_fails_at_boot_rather_than_silently_meaning_on
    assert_raises(ArgumentError) { enable(:hard) }
    assert_raises(ArgumentError) { enable("yes") }
  end

  # =========================================================================
  # The confirmation itself
  # =========================================================================

  def test_a_model_without_the_concern_still_gets_the_confirmable_error
    # And no way past it, which is why the README tells hosts to wire the
    # checkbox before switching this on.
    enable
    user = User.new(email: "someone@gnail.com")

    refute user.valid?
    assert user.errors.of_kind?(:email, :lookalike_domain)
  end

  def test_checkbox_values_are_cast_like_a_boolean_column
    enable

    %w[1 true on].each { |v| assert ConfirmingUser.new(email: "someone@gnail.com", email_lookalike_confirmed: v).valid? }
    ["0", "false", "", nil].each { |v| refute ConfirmingUser.new(email: "someone@gnail.com", email_lookalike_confirmed: v).valid? }
  end

  def test_the_confirmation_is_virtual_and_starts_false
    user = ConfirmingUser.new(email: "someone@gnail.com")

    assert_equal false, user.email_lookalike_confirmed
    refute user.email_lookalike_confirmed?
    refute ConfirmingUser.column_names.include?("email_lookalike_confirmed")
  end

  def test_a_hand_rolled_confirmation_must_be_exactly_true
    # A truthy string a host forgot to cast must not count as "yes".
    enable
    klass = Class.new(ApplicationRecord) do
      self.table_name = "users"
      attr_accessor :email_lookalike_confirmed
      validates :email, nondisposable: true
      def self.name = "HandRolledUser"
    end

    refute klass.new(email: "someone@gnail.com", email_lookalike_confirmed: "0").valid?
    assert klass.new(email: "someone@gnail.com", email_lookalike_confirmed: true).valid?
  end

  def test_confirmation_never_lets_a_disposable_or_blocked_address_through
    setup_disposable_domain!("tempmail.com")
    enable(:confirmable, check_tld: true, blocked_tlds: %w[tk])

    refute confirmed("someone@tempmail.com").valid?
    refute confirmed("someone@gmail.tk").valid?
  end

  def test_confirmation_is_per_attribute
    enable
    klass = Class.new(ApplicationRecord) do
      self.table_name = "contacts"
      include Nondisposable::ConfirmableEmail
      confirmable_email :contact_email
      validates :contact_email, nondisposable: true
      def self.name = "ConfirmingContact"
    end

    assert klass.new(contact_email: "someone@gnail.com", contact_email_lookalike_confirmed: "1").valid?
    refute klass.new(contact_email: "someone@gnail.com").valid?
  end

  def test_still_at_most_one_error
    enable(:confirmable, check_tld: true)
    user = ConfirmingUser.new(email: "someone@gnail.com")

    refute user.valid?
    assert_equal 1, user.errors[:email].size
  end

  # =========================================================================
  # Host overrides
  # =========================================================================

  def test_a_host_provider_outranks_the_known_typo_list
    # A host that says a domain is a real provider for its users has told us
    # something our review could not know.
    enable
    typo = Nondisposable::KnownTypos.all.keys.first
    Nondisposable.configuration.additional_email_providers = [typo]

    assert User.new(email: "someone@#{typo}").valid?
  end

  def test_a_known_typo_without_a_local_part_is_still_refused
    enable
    user = confirmed("@gmial.com")

    refute user.valid?
    assert_includes user.errors[:email], "looks like a typo. Did you mean gmail.com?"
  end

  def test_an_ideographic_dot_does_not_turn_a_question_into_a_wall
    # `gnail。com` is `gnail.com` typed on a CJK keyboard: confirmable, not an
    # "impossible TLD".
    enable

    assert confirmed("someone@gnail。com").valid?
  end

  def test_a_confirmation_answers_for_one_save
    enable
    user = confirmed("someone@gnail.com")
    assert user.save

    user.email = "someone@hotnail.com"
    refute user.valid?, "a later lookalike must be asked about again"
  ensure
    ConfirmingUser.delete_all
  end

  def test_the_known_typo_list_matches_through_case_and_the_root_dot
    enable
    typo = Nondisposable::KnownTypos.all.keys.first

    refute confirmed("someone@#{typo.upcase}.").valid?
  end

  # =========================================================================
  # A reviewed typo the blocklist also lists (0.6.2)
  #
  # Upstream lists carry some of our reviewed typos (the bundled snapshot has
  # gmial.com, hotmai.com and hotmial.com). Both verdicts refuse the address;
  # these tests pin which MESSAGE wins: the correction, because it is the one
  # that is true about the person typing.
  # =========================================================================

  def test_a_known_typo_in_the_bundled_blocklist_gets_its_correction_once_the_table_is_loaded
    assert Nondisposable::DomainListUpdater.seed
    enable

    { "gmial.com" => "gmail.com", "hotmai.com" => "hotmail.com", "hotmial.com" => "hotmail.com" }.each do |typo, correction|
      # Not vacuous: the table really does list it.
      assert Nondisposable.disposable?("ana@#{typo}"), "#{typo} is expected in the bundled blocklist"

      user = confirmed("ana@#{typo}")
      refute user.valid?
      assert_equal ["looks like a typo. Did you mean ana@#{correction}?"], user.errors[:email]
      refute user.errors.of_kind?(:email, :lookalike_domain), "a reviewed typo is hard, listed or not"
    end
  end

  def test_every_known_typo_gets_its_correction_even_if_a_blocklist_lists_it
    # The worst case, independent of today's upstream data: every reviewed
    # typo listed as a throwaway. The daily update can add any of them.
    Nondisposable::KnownTypos.all.each_key { |typo| setup_disposable_domain!(typo) }
    enable

    Nondisposable::KnownTypos.all.each do |typo, correction|
      user = confirmed("someone@#{typo}")
      refute user.valid?
      assert_equal ["looks like a typo. Did you mean someone@#{correction}?"], user.errors[:email], typo
    end
  end

  def test_a_listed_known_typo_without_a_local_part_names_the_domain
    setup_disposable_domain!("gmial.com")
    enable

    user = User.new(email: "@gmial.com")
    refute user.valid?
    assert_equal ["looks like a typo. Did you mean gmail.com?"], user.errors[:email]
  end

  def test_the_correction_also_outranks_a_custom_throwaway_message
    setup_disposable_domain!("gmial.com")
    setup_disposable_domain!("tempmail.com")
    enable

    typo = Subscriber.new(email: "ana@gmial.com")
    refute typo.valid?
    assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], typo.errors[:email]

    throwaway = Subscriber.new(email: "ana@tempmail.com")
    refute throwaway.valid?
    assert_equal ["is a throwaway address"], throwaway.errors[:email]
  end

  def test_a_listed_impossible_tld_with_a_correction_gets_the_correction
    # The other HARD correction. With check_tld alone, as with the lookalike
    # layer on: no mail reaches `.con`, so a blocklist entry adds nothing.
    setup_disposable_domain!("gmail.con")
    Nondisposable.configuration.check_tld = true

    user = User.new(email: "ana@gmail.con")
    refute user.valid?
    assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], user.errors[:email]
  end

  def test_a_guess_the_blocklist_lists_is_still_refused_as_a_throwaway
    # `gotmail.com` is one finger from hotmail.com AND a listed throwaway in
    # the bundled snapshot. A guess is confirmable; asking "did you mean
    # hotmail.com?" would let the user tick "yes" only to be refused anyway.
    assert Nondisposable::DomainListUpdater.seed
    enable
    assert_equal "ana@hotmail.com", Nondisposable.suggestion_for("ana@gotmail.com")
    refute Nondisposable::KnownTypos.include?("gotmail.com")

    [ConfirmingUser.new(email: "ana@gotmail.com"), confirmed("ana@gotmail.com")].each do |user|
      refute user.valid?
      assert_equal ["provider is not allowed"], user.errors[:email]
      refute user.errors.of_kind?(:email, :lookalike_domain)
    end
  end

  def test_with_the_lookalike_layer_off_a_listed_typo_keeps_the_throwaway_message
    # Nothing about the order changes for hosts that never switched it on:
    # the table refuses gmial.com, as it always has.
    setup_disposable_domain!("gmial.com")

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["provider is not allowed"], user.errors[:email]

    enable(:confirmable, lookalike_distance: 0)
    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["provider is not allowed"], user.errors[:email]
  end

  def test_a_host_provider_listed_as_a_throwaway_is_refused_as_a_throwaway
    # additional_email_providers takes a domain off the known-typo list; it
    # does not unlist it. With no correction to offer, the table speaks.
    setup_disposable_domain!("gmial.com")
    enable(:confirmable, additional_email_providers: %w[gmial.com])

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["provider is not allowed"], user.errors[:email]
  end

  def test_a_certain_correction_needs_no_database
    # A reviewed typo is known before the blocklist is asked, so a lookup that
    # raises can neither wave it through (:allow) nor swap the correction
    # for the generic infrastructure error (:reject).
    enable
    %i[allow reject].each do |mode|
      Nondisposable.configuration.on_check_failure = mode
      Nondisposable::DisposableDomain.stub(:disposable?, ->(*) { raise "database down" }) do
        user = confirmed("ana@gmial.com")
        refute user.valid?, "on_check_failure = #{mode.inspect} must still refuse a reviewed typo"
        assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], user.errors[:email]
      end
    end
  end

  def test_an_impossible_tld_correction_needs_no_database
    Nondisposable.configuration.check_tld = true
    Nondisposable::DisposableDomain.stub(:disposable?, ->(*) { raise "database down" }) do
      user = User.new(email: "ana@gmail.con")
      refute user.valid?
      assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], user.errors[:email]
    end
  end

  def test_a_listed_throwaway_never_pays_for_the_ranker
    # The ranker is the expensive part (a distance walk over ~250 providers)
    # and a guess never outranks the blocklist, so a listed throwaway with no
    # certain correction must be refused without running it.
    setup_disposable_domain!("tempmail.com")
    setup_disposable_domain!("gotmail.com")
    enable(:confirmable, check_tld: true)

    Nondisposable::Suggestion.stub(:guess, ->(*) { flunk "the ranker ran for a listed throwaway" }) do
      %w[ana@tempmail.com ana@gotmail.com].each do |email|
        user = User.new(email: email)
        refute user.valid?
        assert_equal ["provider is not allowed"], user.errors[:email]
      end
    end
  end

  # =========================================================================
  # lookalike_error_message: String, I18n key or callable (0.6.2)
  # =========================================================================

  def test_a_symbol_is_an_i18n_key_interpolated_with_the_suggestion
    I18n.backend.store_translations(:en, nondisposable_test: { typo: "is misspelt. Try %{suggestion}" })
    enable(:confirmable, lookalike_error_message: :"nondisposable_test.typo")

    hard = confirmed("ana@gmial.com")
    refute hard.valid?
    assert_equal ["is misspelt. Try ana@gmail.com"], hard.errors[:email]

    guess = ConfirmingUser.new(email: "ana@gnail.com")
    refute guess.valid?
    assert_equal ["is misspelt. Try ana@gmail.com"], guess.errors[:email]
    assert guess.errors.of_kind?(:email, :lookalike_domain)
    assert_equal "ana@gmail.com", guess.errors.details[:email].first[:suggestion]
  end

  def test_a_symbol_answers_in_the_locale_of_the_validation_not_of_the_initializer
    available = I18n.available_locales
    I18n.available_locales = available | [:es]
    I18n.backend.store_translations(:en, nondisposable_test: { typo: "looks like a typo. Did you mean %{suggestion}?" })
    I18n.backend.store_translations(:es, nondisposable_test: { typo: "parece una errata. ¿Querías decir %{suggestion}?" })
    enable(:confirmable, lookalike_error_message: :"nondisposable_test.typo")

    I18n.with_locale(:es) do
      user = User.new(email: "ana@gmial.com")
      refute user.valid?
      assert_equal ["parece una errata. ¿Querías decir ana@gmail.com?"], user.errors[:email]
    end

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], user.errors[:email]
  ensure
    I18n.available_locales = available
  end

  def test_a_symbol_with_no_translation_falls_back_to_the_default_message
    # Never "Translation missing" in front of a user, and never an exception
    # that on_check_failure = :allow would turn into an accepted typo.
    enable(:confirmable, lookalike_error_message: :"nondisposable_test.no_such_key")

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], user.errors[:email]
  end

  def test_a_callable_is_called_with_the_suggestion
    enable(:confirmable, lookalike_error_message: ->(suggestion) { "should be #{suggestion}" })

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["should be ana@gmail.com"], user.errors[:email]

    no_local_part = User.new(email: "@gmial.com")
    refute no_local_part.valid?
    assert_equal ["should be gmail.com"], no_local_part.errors[:email]
  end

  def test_a_string_still_interpolates_exactly_as_before
    enable(:confirmable, lookalike_error_message: "is wrong (%{suggestion}?)")

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["is wrong (ana@gmail.com?)"], user.errors[:email]
  end

  def test_an_object_that_answers_sub_keeps_working
    # The only way to localise this message before 0.6.2; hosts that did it
    # must not break on upgrade.
    localised = Object.new
    def localised.sub(_placeholder, suggestion) = "custom #{suggestion}"
    enable(:confirmable, lookalike_error_message: localised)

    user = User.new(email: "ana@gmial.com")
    refute user.valid?
    assert_equal ["custom ana@gmail.com"], user.errors[:email]
  end

  def test_a_translation_missing_an_interpolation_argument_still_refuses
    # I18n's default: covers a missing key, not a translation that raises.
    # A raise used to reach the validator's rescue, where :allow ACCEPTED a
    # listed reviewed typo.
    setup_disposable_domain!("gmial.com")
    I18n.backend.store_translations(:en, nondisposable_test: { bad_var: "Did you mean %{address}?" })
    enable(:confirmable, lookalike_error_message: :"nondisposable_test.bad_var")

    assert_refused_with_the_default_message("ana@gmial.com")
  end

  def test_a_raising_translation_proc_still_refuses
    setup_disposable_domain!("gmial.com")
    I18n.backend.store_translations(:en, nondisposable_test: { raising: ->(*) { raise "boom" } })
    enable(:confirmable, lookalike_error_message: :"nondisposable_test.raising")

    assert_refused_with_the_default_message("ana@gmial.com")
  end

  def test_a_raising_callable_still_refuses
    setup_disposable_domain!("gmial.com")
    enable(:confirmable, lookalike_error_message: ->(_suggestion) { raise "boom" })

    assert_refused_with_the_default_message("ana@gmial.com")
    # The confirmable error goes through the same resolution.
    guess = ConfirmingUser.new(email: "ana@gnail.com")
    refute guess.valid?
    assert guess.errors.of_kind?(:email, :lookalike_domain)
    assert_equal ["looks like a typo. Did you mean ana@gmail.com?"], guess.errors[:email]
  end

  private

  def assert_refused_with_the_default_message(email)
    log = capture_log do
      user = User.new(email: email)
      refute user.valid?, "a broken message must never turn a refusal into an acceptance"
      assert_equal ["looks like a typo. Did you mean #{email.sub('gmial', 'gmail')}?"], user.errors[:email]
    end
    assert_match(/lookalike_error_message/, log)
  end
end
