# frozen_string_literal: true

require "test_helper"

# The lookalike layer: "did you mean gmail.com?"
#
# The false-positive tests below matter more than the true-positive ones. A
# missed typo is a bad address in the database; a wrong suggestion wired to
# `reject_lookalike_domains` is a real person who cannot sign up with their real
# address. If a change to the provider list or the distance threshold breaks
# anything here, it is the wrong change.
class NondisposableSuggestionTest < NondisposableTestCase
  # =========================================================================
  # The typos a TLD check structurally cannot catch
  # =========================================================================

  def test_corrects_a_real_but_wrong_tld
    # .co, .cm and .om are Colombia, Cameroon and Oman — all real, so the root
    # zone has nothing to say about them. This is the only layer that can.
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmail.co")
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmail.cm")
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmail.om")
  end

  def test_corrects_transposed_letters
    # The single most common Gmail misspelling. Plain Levenshtein scores this 2
    # and would miss it at the default threshold; optimal string alignment
    # scores the swap as the one mistake a human actually made.
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmial.com")
    assert_equal "someone@hotmail.com", Nondisposable.suggestion_for("someone@hotmial.com")
  end

  def test_corrects_dropped_and_doubled_letters
    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmai.com")
    assert_equal "someone@yahoo.com", Nondisposable.suggestion_for("someone@yaho.com")
    assert_equal "someone@outlook.com", Nondisposable.suggestion_for("someone@outlok.com")
    assert_equal "someone@icloud.com", Nondisposable.suggestion_for("someone@iclod.com")
  end

  def test_corrects_the_three_typo_shapes_observed_in_production
    # Synthetic local parts preserve the three measured failure shapes without
    # putting customer addresses into this public repository.
    assert_equal "example@gmail.com", Nondisposable.suggestion_for("example@gmailmcom")
    assert_equal "example@outlook.es", Nondisposable.suggestion_for("example@outlook.ed")
    assert_equal "example@gmail.com", Nondisposable.suggestion_for("example@gmail.con")
  end

  def test_preserves_the_local_part_exactly
    # Including its case: local parts are case-sensitive per RFC 5321, and it is
    # not our place to normalise somebody's address while correcting a typo.
    assert_equal "First.Last+tag@gmail.com", Nondisposable.suggestion_for("First.Last+tag@gmial.com")
  end

  # =========================================================================
  # False positives — the tests that matter most
  # =========================================================================

  def test_never_suggests_for_a_provider_on_the_list
    %w[gmail.com hotmail.com outlook.com yahoo.com icloud.com proton.me
       hotmail.es outlook.es terra.es web.de qq.com 163.com mail.ru].each do |domain|
      assert_nil Nondisposable.suggestion_for("someone@#{domain}"),
        "#{domain} is a real provider and must never be called a typo"
    end
  end

  def test_never_suggests_for_mail_dot_com
    # The canonical trap: mail.com is a real provider exactly one insertion away
    # from gmail.com. It is on the bundled list precisely so that its users are
    # not told they mistyped their own address.
    assert_nil Nondisposable.suggestion_for("someone@mail.com")
  end

  def test_never_suggests_for_short_providers_that_sit_near_each_other
    # 163.com/126.com and ya.com/qq.com are all real and all short, where a
    # single edit is a large relative change.
    %w[163.com 126.com ya.com qq.com me.com aol.com].each do |domain|
      assert_nil Nondisposable.suggestion_for("someone@#{domain}")
    end
  end

  def test_never_suggests_for_ordinary_company_domains
    %w[carhey.com especialistasweb.es some-random-company.io acme.co
       bbc.co.uk stripe.com github.com].each do |domain|
      assert_nil Nondisposable.suggestion_for("someone@#{domain}"),
        "#{domain} is a normal domain, not a typo of a consumer provider"
    end
  end

  # =========================================================================
  # The ranker: what one edit cannot tell apart (since 0.5.0)
  # =========================================================================

  def test_short_provider_names_only_take_edits_after_the_name
    # me, ya, aol, mail, live: one edit inside a name this short is usually
    # somebody else's real domain (General Electric, EA, bol.com, Mil.ru…).
    %w[ge.com ml.com mi.com ea.com aa.com bol.com uol.com one.com mil.ru love.com hive.com].each do |domain|
      assert_nil Nondisposable::Suggestion.correct_domain(domain), "#{domain} must not be called a typo"
    end
    # The ending is still fair game.
    assert_equal "me.com", Nondisposable::Suggestion.correct_domain("me.cmo")
    assert_equal "live.com", Nondisposable::Suggestion.correct_domain("live.cm")
  end

  def test_a_letter_from_across_the_keyboard_is_a_different_word
    %w[grail.com pmail.com qmail.com].each do |domain|
      assert_nil Nondisposable::Suggestion.correct_domain(domain), "#{domain} is not a finger slip"
    end
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("gnail.com")   # n is beside m
    assert_equal "hotmail.com", Nondisposable::Suggestion.correct_domain("hotnail.com")
  end

  def test_valid_alternative_endings_are_not_slips
    # Yahoo Australia and Google's web.dev are real; .au is not a slip for
    # .ar, nor .dev for .de.
    assert_nil Nondisposable::Suggestion.correct_domain("yahoo.com.au")
    assert_nil Nondisposable::Suggestion.correct_domain("web.dev")
    assert_nil Nondisposable::Suggestion.correct_domain("yahoo.in")
  end

  def test_dropping_the_first_letter_spells_other_peoples_domains
    # cloud.com, aver.com and mail.ch are icloud, naver and gmail.ch without
    # their first letter — and all three are real.
    %w[cloud.com aver.com mail.ch].each do |domain|
      assert_nil Nondisposable::Suggestion.correct_domain(domain)
    end
  end

  def test_extra_vowels_and_doubled_letters_are_slips
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("gmmail.com")
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("gamail.com")
  end

  def test_an_accent_is_the_same_key
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("gmaíl.com")
    assert_equal "hotmail.com", Nondisposable::Suggestion.correct_domain("hotmaíl.com")
  end

  def test_a_reviewed_typo_is_corrected_even_where_the_ranker_would_stay_silent
    # jmail.com: j is not beside g, so the ranker alone says nothing — but it
    # is a reviewed typo (data/known_typo_domains.txt), so the list answers.
    assert_nil Nondisposable::Suggestion.guess("jmail.com")
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("jmail.com")
  end

  def test_subdomains_and_country_second_levels_are_left_alone
    %w[alumnos.upm.es correo.ugr.es bbc.co.uk empresa.com.es loja.com.br].each do |domain|
      assert_nil Nondisposable::Suggestion.correct_domain(domain), "#{domain} is not a typo"
    end
  end

  def test_returns_nil_for_input_it_cannot_read
    assert_nil Nondisposable.suggestion_for(nil)
    assert_nil Nondisposable.suggestion_for("")
    assert_nil Nondisposable.suggestion_for("not-an-email")
    assert_nil Nondisposable.suggestion_for("@gmail.com")
    assert_nil Nondisposable.suggestion_for("someone@")
  end

  def test_correcting_a_bare_domain_handles_nothing_gracefully
    # correct_domain is public so a host can put "did you mean …?" next to a
    # domain field, not only an email one — so it takes whatever that field had.
    assert_nil Nondisposable::Suggestion.correct_domain("")
    assert_nil Nondisposable::Suggestion.correct_domain(nil)
    assert_nil Nondisposable::Suggestion.correct_domain("   ")
    assert_equal "gmail.com", Nondisposable::Suggestion.correct_domain("GMIAL.COM")
    # A fully-qualified trailing dot is the same host, not a different one.
    assert_nil Nondisposable::Suggestion.correct_domain("gmail.com.")
  end

  # =========================================================================
  # Configuration
  # =========================================================================

  def test_additional_providers_become_both_candidates_and_shields
    Nondisposable.configure { |c| c.additional_email_providers = ["carhey.com"] }

    # A shield: the added domain is never called a typo of anything.
    assert_nil Nondisposable.suggestion_for("someone@carhey.com")
    # A candidate: near-misses of it now get corrected.
    assert_equal "someone@carhey.com", Nondisposable.suggestion_for("someone@carhye.com")
  end

  def test_distance_zero_turns_suggestions_off
    Nondisposable.configure { |c| c.lookalike_distance = 0 }

    assert_nil Nondisposable.suggestion_for("someone@gmial.com")
  end

  def test_a_wider_threshold_catches_more_and_is_therefore_riskier
    # Documented, not recommended. At 2, ccTLD variants of the same brand start
    # colliding — which is the whole reason the default is 1.
    assert_nil Nondisposable.suggestion_for("someone@gmaill.comm")

    Nondisposable.configure { |c| c.lookalike_distance = 2 }

    assert_equal "someone@gmail.com", Nondisposable.suggestion_for("someone@gmaill.comm")
  end
end
