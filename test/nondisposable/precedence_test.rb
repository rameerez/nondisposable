# frozen_string_literal: true

require "test_helper"

# The ONE precedence table, row by row, both where it is enforced at check time
# (DisposableDomain.disposable?) and where it is enforced when the list is
# built (Precedence.filter):
#
#   1. excluded_domains   > 2. never_disposable > 3. additional_domains
#   > 4. privacy relays (block_privacy_relays) > 5. merged sources
class NondisposablePrecedenceTest < NondisposableTestCase
  P = Nondisposable::Precedence

  def disposable?(domain)
    Nondisposable::DisposableDomain.disposable?(domain)
  end

  def kept(domains)
    P.filter(domains).kept.to_a.sort
  end

  # =========================================================================
  # Check time: each row against every row below it
  # =========================================================================

  def test_row5_a_listed_domain_is_blocked
    setup_disposable_domain!("tempmail.com")
    assert disposable?("tempmail.com")
  end

  def test_row4_relays_are_allowed_by_default_even_when_listed
    setup_disposable_domain!("duck.com")
    refute disposable?("duck.com")
  end

  def test_row4_relays_are_blocked_on_request_even_when_unlisted
    Nondisposable.configuration.block_privacy_relays = true
    assert disposable?("duck.com")
    assert disposable?("privaterelay.appleid.com")
  end

  def test_row4_relay_policy_covers_relay_subdomains
    Nondisposable.configuration.block_privacy_relays = true
    assert disposable?("someone.anonaddy.com")

    Nondisposable.configuration.block_privacy_relays = false
    setup_disposable_domain!("anonaddy.com")
    refute disposable?("someone.anonaddy.com")
  end

  def test_row3_additional_beats_relay_policy
    Nondisposable.configuration.additional_domains = ["duck.com"]
    assert disposable?("duck.com"), "a host addition outranks the default relay allowance"
  end

  def test_row3_additional_beats_an_unlisted_domain
    Nondisposable.configuration.additional_domains = ["mail-burn.com"]
    assert disposable?("mail-burn.com")
  end

  def test_row2_never_disposable_beats_the_stored_list
    setup_disposable_domain!("sify.com")
    refute disposable?("sify.com")
  end

  def test_row2_never_disposable_beats_additional_domains
    Nondisposable.configuration.additional_domains = ["gmail.com"]
    refute disposable?("gmail.com")
  end

  def test_row2_never_disposable_protects_subdomains
    # Upstream lists really carry Spectrum's regional rr.com subdomains.
    setup_disposable_domain!("bak.rr.com")
    refute disposable?("bak.rr.com")
  end

  def test_row2_never_disposable_ignores_check_parent_domains_false
    Nondisposable.configuration.check_parent_domains = false
    setup_disposable_domain!("bak.rr.com")
    refute disposable?("bak.rr.com")
  end

  def test_row1_exclusion_beats_additional_domains
    Nondisposable.configuration.additional_domains = ["overlap.com"]
    Nondisposable.configuration.excluded_domains = ["overlap.com"]
    refute disposable?("overlap.com")
  end

  def test_row1_exclusion_beats_relay_blocking
    Nondisposable.configuration.block_privacy_relays = true
    Nondisposable.configuration.excluded_domains = ["duck.com"]
    refute disposable?("duck.com")
  end

  def test_row1_excluded_parent_cannot_be_the_reason_for_a_relay_block
    Nondisposable.configuration.block_privacy_relays = true
    Nondisposable.configuration.excluded_domains = ["anonaddy.com"]
    refute disposable?("someone.anonaddy.com")
  end

  def test_row1_excluded_parent_still_lets_a_listed_subdomain_block
    # Unchanged since 0.3.0: an excluded parent stops being a reason, a more
    # specific listing still is one.
    setup_disposable_domain!("x.tempmail.com")
    Nondisposable.configuration.excluded_domains = ["tempmail.com"]
    assert disposable?("x.tempmail.com")
  end

  def test_row1_excluded_parent_does_not_block_via_additional
    Nondisposable.configuration.additional_domains = ["tempmail.com"]
    Nondisposable.configuration.excluded_domains = ["tempmail.com"]
    refute disposable?("x.tempmail.com")
  end

  def test_public_suffix_rows_never_match
    Nondisposable::DisposableDomain.insert_all([{ name: "com.br" }, { name: "github.io" }], record_timestamps: true)
    Nondisposable.configuration.additional_domains = ["co.uk"]

    refute disposable?("empresa.com.br")
    refute disposable?("someone.github.io")
    refute disposable?("bbc.co.uk")
  end

  def test_checks_are_case_dot_and_idn_insensitive
    setup_disposable_domain!("xn--bcher-kva.de")
    assert disposable?("BÜCHER.de.")
    assert Nondisposable.disposable?("Someone+Tag@Bücher.DE")
  end

  def test_decide_returns_lookup_candidates_without_exclusions
    Nondisposable.configuration.excluded_domains = ["tempmail.com"]
    verdict, candidates = P.decide("x.tempmail.com", ["x.tempmail.com", "tempmail.com"])
    assert_equal :lookup, verdict
    assert_equal ["x.tempmail.com"], candidates
  end

  # =========================================================================
  # Build time: the same table applied to a list about to be stored
  # =========================================================================

  def test_filter_keeps_ordinary_domains
    assert_equal %w[a.com b.net], kept(%w[a.com b.net])
  end

  def test_filter_drops_invalid_and_public_suffix_entries
    result = P.filter(%w[ok.com com.br it.com com bad..com -x.com 1.2.3.4])
    assert_equal %w[ok.com], result.kept.to_a
    reasons = result.dropped_by_reason
    assert_equal %w[com.br it.com], reasons[:public_suffix]
    assert_equal %w[-x.com 1.2.3.4 bad..com com], reasons[:invalid]
  end

  def test_filter_drops_never_disposable_and_their_subdomains
    result = P.filter(%w[temp.com gmail.com bak.rr.com])
    assert_equal %w[temp.com], result.kept.to_a
    assert_equal %w[bak.rr.com gmail.com], result.dropped_by_reason[:never_disposable]
  end

  def test_filter_drops_relays_unless_blocking_them
    assert_equal %w[temp.com], kept(%w[temp.com duck.com x.anonaddy.com])

    Nondisposable.configuration.block_privacy_relays = true
    assert_equal %w[duck.com temp.com x.anonaddy.com], kept(%w[temp.com duck.com x.anonaddy.com])
  end

  def test_filter_drops_exact_exclusions_only
    Nondisposable.configuration.excluded_domains = ["Temp.com"]
    assert_equal %w[x.temp.com], kept(%w[temp.com x.temp.com])
  end

  def test_filter_adds_additional_domains_through_rows_1_and_2
    Nondisposable.configuration.additional_domains = ["Mail-Burn.com.", "gmail.com", "co.uk", "", "excluded.com"]
    Nondisposable.configuration.excluded_domains = ["excluded.com"]

    result = P.filter(%w[temp.com])
    assert_equal %w[mail-burn.com temp.com], result.kept.to_a.sort
    assert_equal %w[gmail.com], result.dropped_by_reason[:additional_domain_is_never_disposable]
    assert_equal %w[co.uk], result.dropped_by_reason[:invalid_additional_domain]
  end

  # =========================================================================
  # The bundled lists
  # =========================================================================

  def test_relays_are_never_permanently_exempt
    # Otherwise block_privacy_relays = true could never work.
    assert P.privacy_relays.none? { |relay| P.never_disposable.include?(relay) }
    assert_includes P.privacy_relays, "duck.com"
    refute_includes P.never_disposable, "duck.com" # it IS in email_providers.txt
  end

  def test_never_disposable_unions_the_provider_list
    assert_includes P.never_disposable, "gmail.com"   # email_providers.txt
    assert_includes P.never_disposable, "gmx.es"      # never_disposable.txt
    assert_includes P.never_disposable, "fastmail.fm" # paid providers section
  end

  def test_every_bundled_entry_is_a_storable_domain
    (P.never_disposable | P.privacy_relays).each do |domain|
      assert_nil P.invalid_reason(domain), "#{domain} in a bundled list is #{P.invalid_reason(domain).inspect}"
    end
  end

  def test_measured_upstream_false_positives_are_protected
    %w[sify.com broadpark.no ybb.ne.jp riseup.net ukr.net freemail.hu sohu.com windstream.net
       mail.ru qq.com naver.com gmx.es 21cn.com tom.com wo.com.cn odn.ad.jp].each do |domain|
      assert P.namespace_hit(domain, P.never_disposable), "#{domain} should be never-disposable"
    end
  end

  def test_namespace_skips_public_suffixes
    assert_equal %w[a.b.rr.com b.rr.com rr.com], P.namespace("a.b.rr.com")
    assert_equal %w[bbc.co.uk], P.namespace("bbc.co.uk")
    assert_equal [], P.namespace("com")
  end

  def test_hostname_rules
    assert P.hostname?("a.co")
    assert P.hostname?("under_score.com")
    assert P.hostname?("#{'a' * 63}.com")
    refute P.hostname?("#{'a' * 64}.com")
    refute P.hostname?((["a" * 60] * 5).join(".") + ".com") # > 253
    refute P.hostname?("localhost")
    refute P.hostname?("")
    refute P.hostname?("trailing.")
    refute P.hostname?("<html>")
    refute P.hostname?("10.0.0.1")
  end

  def test_reload_clears_memoized_lists
    P.never_disposable
    assert_same P, P.reload!
    assert_includes P.never_disposable, "gmail.com"
  end
end
