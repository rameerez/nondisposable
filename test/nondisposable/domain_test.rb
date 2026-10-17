# frozen_string_literal: true

require "test_helper"

# One canonical form per host. If two spellings of the same domain can get
# different verdicts, a list entry can be dodged by typing it differently —
# or, worse, a provider exemption can be missed and a real user flagged.
class NondisposableDomainTest < NondisposableTestCase
  def normalize(value)
    Nondisposable::Domain.normalize(value)
  end

  def test_case_whitespace_and_the_root_dot_are_not_part_of_the_name
    assert_equal "gmail.com", normalize("  GMail.COM. ")
    assert_equal "gmail.com", normalize("gmail.com\n")
  end

  def test_unicode_domains_become_their_punycode_form
    # Published IDNA vectors: these are the strings a resolver actually asks
    # for, and the form every blocklist stores.
    assert_equal "xn--bcher-kva.de", normalize("bücher.de")
    assert_equal "xn--mnchen-3ya.de", normalize("MÜNCHEN.de")
    assert_equal "xn--fiqs8s", normalize("中国")
    assert_equal "xn--r8jz45g.xn--zckzah", normalize("例え.テスト")
    assert_equal "xn--and-6ma2c.es", normalize("ñandú.es")
  end

  def test_unicode_and_punycode_spellings_are_the_same_domain
    assert_equal normalize("xn--bcher-kva.de"), normalize("bücher.de")
    assert_equal normalize("XN--BCHER-KVA.DE"), normalize("Bücher.DE")
  end

  def test_composed_and_decomposed_accents_are_the_same_domain
    # "ü" can arrive as one code point or as "u" + combining diaeresis
    # depending on the keyboard and OS. Both must land on one name.
    assert_equal normalize("bücher.de"), normalize("bücher.de")
  end

  def test_ideographic_full_stops_separate_labels
    assert_equal "example.com", normalize("example。com")
    assert_equal "example.com", normalize("example．com")
  end

  def test_compatibility_forms_and_invisible_characters_are_folded
    # UTS #46 maps these before lookup, and so must we: otherwise a listed
    # domain is dodged by typing it fullwidth or with a soft hyphen inside.
    assert_equal "mailinator.com", normalize("ｍａｉｌｉｎａｔｏｒ.com")
    assert_equal "mailinator.com", normalize("maili­nator.com")
    assert_equal "mailinator.com", normalize("mail​inator.com")
  end

  def test_an_oversized_unicode_label_is_not_encoded
    # Longer than DNS allows, so it cannot be anybody's domain — and encoding
    # it would be quadratic work on attacker-controlled input.
    huge = (0x4E00...(0x4E00 + 4000)).to_a.pack("U*")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_equal "#{huge}.com", normalize("#{huge}.com")
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.1
    refute Nondisposable.disposable?("x@#{huge}.com")
  end

  def test_blank_and_unreadable_input_is_harmless
    assert_equal "", normalize(nil)
    assert_equal "", normalize("   ")
    # Bytes that are not UTF-8 are not a domain anyone typed; they must not
    # raise inside a validator.
    refute_nil normalize("ma\xFFil.com".dup.force_encoding("UTF-8"))
  end

  def test_from_email_takes_the_domain_and_never_touches_the_local_part
    assert_equal "gmail.com", Nondisposable::Domain.from_email("First.Last+Tag@GMail.com.")
    assert_equal "example.com", Nondisposable::Domain.from_email('"user@local"@Example.com')
    assert_equal "tempmail.com", Nondisposable::Domain.from_email("@tempmail.com")
    assert_equal "", Nondisposable::Domain.from_email("no-at-sign")
    assert_equal "", Nondisposable::Domain.from_email("user@")
  end

  def test_subdomains_and_country_second_levels_are_kept_whole
    # Normalising is not shortening: a university subdomain or a co.uk
    # registration is its own name, and stripping labels would match it
    # against somebody else's list entry.
    assert_equal "alumnos.upm.es", normalize("Alumnos.UPM.es")
    assert_equal "bbc.co.uk", normalize("bbc.co.uk")
    assert_equal "uol.com.br", normalize("UOL.com.br")
    assert_equal "empresa.com.es", normalize("empresa.com.es.")
  end

  # =========================================================================
  # Every path judges the same name
  # =========================================================================

  def test_the_disposable_check_sees_through_case_and_the_root_dot
    setup_disposable_domain!("tempmail.com")

    assert Nondisposable.disposable?("user@TempMail.com.")
    refute User.new(email: "user@tempmail.com.").valid?
  end

  def test_the_disposable_check_matches_a_unicode_domain_by_its_punycode_entry
    setup_disposable_domain!("xn--bcher-kva.de")

    assert Nondisposable.disposable?("user@bücher.de")
    refute User.new(email: "user@bücher.de").valid?
  end

  def test_a_fullwidth_or_soft_hyphenated_disposable_domain_is_still_caught
    setup_disposable_domain!("mailinator.com")

    refute User.new(email: "x@ｍａｉｌｉｎａｔｏｒ.com").valid?
    refute User.new(email: "x@maili­nator.com").valid?
  end

  def test_a_unicode_exclusion_matches_its_punycode_list_entry
    setup_disposable_domain!("xn--bcher-kva.de")
    Nondisposable.configure { |c| c.excluded_domains = ["bücher.de"] }

    assert User.new(email: "x@bücher.de").valid?
  end

  def test_a_unicode_addition_blocks_its_punycode_spelling
    Nondisposable.configure { |c| c.additional_domains = ["bücher.de"] }

    refute User.new(email: "x@xn--bcher-kva.de").valid?
  end

  def test_the_tld_path_reads_fullwidth_and_ideographic_dots_as_dots
    Nondisposable.configure do |c|
      c.check_tld = true
      c.blocked_tlds = %w[tk]
    end

    refute User.new(email: "x@foo.bar．tk").valid?
    refute User.new(email: "x@foo.bar．con").valid?
    refute Nondisposable.valid_tld?("x@foo。con")
    assert User.new(email: "x@empresa。es").valid?
  end

  def test_suggestions_see_through_case_and_the_root_dot
    assert_equal "Someone@gmail.com", Nondisposable.suggestion_for("Someone@GMIAL.COM.")
    assert_nil Nondisposable.suggestion_for("someone@GMAIL.COM.")
  end

  def test_suggestions_judge_what_was_typed_not_its_encoding
    # `gmaíl` is one keystroke from `gmail`; its punycode, `xn--gmal-xpa`,
    # is an encoding with no keyboard meaning and gets no guess at all.
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmaíl.com")
    assert_nil Nondisposable.suggestion_for("someone@xn--gmal-xpa.com")
  end

  def test_a_provider_typed_in_another_case_or_with_a_root_dot_is_still_a_provider
    Nondisposable.configure { |c| c.additional_email_providers = ["Carhey.COM."] }

    assert_nil Nondisposable.suggestion_for("someone@carhey.com")
    assert_equal "someone@carhey.com", Nondisposable.suggestion_for("someone@carhye.com")
  end
  # =========================================================================
  # Round-2 review regressions (docs/reviews/2026-10-17-pr5-triage.md)
  # =========================================================================

  def test_zero_width_joiners_are_part_of_the_name
    # UTS #46 nontransitional: ZWNJ/ZWJ are "deviation" characters that
    # IDNA2008 keeps, so these are two different registered domains.
    assert_equal "xn--mgba3gch31f060k.com", normalize("نامه‌ای.com")
    assert_equal "xn--mgba3gch31f.com", normalize("نامهای.com")

    setup_disposable_domain!("xn--mgba3gch31f.com")
    refute Nondisposable.disposable?("x@نامه‌ای.com"), "the ZWNJ spelling is not the listed domain"
    clear_domains!
    setup_disposable_domain!("xn--mgba3gch31f060k.com")
    assert Nondisposable.disposable?("x@نامه‌ای.com"), "and its own entry must still catch it"
  end

  def test_every_ignored_code_point_disappears_on_every_checking_path
    setup_disposable_domain!("mailinator.com")
    refute User.new(email: "x@maili᠎nator.com").valid?
    refute User.new(email: "x@maili\u{E0100}nator.com").valid?

    Nondisposable.configure { |c| c.reject_lookalike_domains = :confirmable }
    user = ConfirmingUser.new(email: "x@gmial.co\u{E0100}m", email_lookalike_confirmed: "1")
    refute user.valid?, "a variation selector must not hide a known typo"

    Nondisposable.configure do |c|
      c.check_tld = true
      c.blocked_tlds = %w[tk]
    end
    refute User.new(email: "x@gmail.t\u{E0100}k").valid?, "nor a blocked TLD"
  end

  def test_hostile_combining_marks_are_bounded_before_normalisation
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    normalize("a#{"̕" * 2000}#{"̀" * 2000}.com")
    User.new(email: "x@a#{"̕" * 2000}#{"̀" * 2000}.com").valid?

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.2
  end

  def test_invisible_padding_cannot_push_a_listed_domain_past_the_length_bound
    setup_disposable_domain!("mailinator.com")

    refute User.new(email: "x@#{"­" * 300}mailinator.com").valid?
  end

  def test_a_unicode_entry_from_a_downloaded_list_is_stored_as_lookups_ask_for_it
    # Through the public path: 0.6.0 replaced the private replace_domains.
    stub_domain_list("bücher.de\n")
    assert Nondisposable::DomainListUpdater.update

    assert_equal ["xn--bcher-kva.de"], Nondisposable::DisposableDomain.pluck(:name)
    assert Nondisposable.disposable?("x@bücher.de")
  end

  def test_a_unicode_row_stored_by_0_4_0_still_blocks_after_upgrading
    setup_disposable_domain!("bücher.de") # how 0.4.0 stored it

    assert Nondisposable.disposable?("x@bücher.de")
    Nondisposable.configure { |c| c.excluded_domains = ["Bücher.de"] }
    refute Nondisposable.disposable?("x@bücher.de"), "an exclusion still wins over a legacy row"
  end

  def test_a_unicode_provider_is_a_ranking_target_as_typed
    Nondisposable.configure do |c|
      c.additional_email_providers = ["bücher.de"]
      c.reject_lookalike_domains = true
    end

    assert_equal "x@bücher.de", Nondisposable.suggestion_for("x@bücehr.de")
    assert_nil Nondisposable.suggestion_for("x@xn--bcher-kva.de"), "the provider itself, in punycode, is exempt"
    refute User.new(email: "x@bücher.d").valid?, "0.4.0 corrected and refused this; so must we"
  end

  def test_binary_and_unreadable_input_never_raises
    assert Nondisposable.valid_tld?("x@bücher.de".b)
    refute Nondisposable.disposable?("x@bücher.de".b)

    ["x@ma\xFFil.com".b, "x@ma\xFFil.com".dup.force_encoding("UTF-8")].each do |value|
      Nondisposable.valid_tld?(value)
      refute Nondisposable.disposable?(value)
      assert_nil Nondisposable.suggestion_for(value)
    end

    Nondisposable.configure { |c| c.check_tld = true }
    assert User.new(email: "x@bücher.de".b).valid?
  end
end
