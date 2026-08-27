# frozen_string_literal: true

require "tmpdir"
require "test_helper"

# The TLD half of the gem: is the bit after the last dot a real top-level
# domain, and does the host want to accept it?
class NondisposableTldTest < NondisposableTestCase
  # =========================================================================
  # The bundled IANA snapshot
  # =========================================================================

  def test_loads_the_whole_root_zone
    # ~1,438 as of the 2026-08 snapshot. The floor guards against a truncated
    # or mangled data file shipping in a release: a root zone with a handful of
    # entries would reject nearly every address on earth.
    assert_operator Nondisposable::Tld.all.size, :>, 1_000
  end

  def test_exposes_the_iana_version_of_the_snapshot
    # Lets a host see how old its list is (e.g. from a health check) without
    # parsing the file itself.
    assert_match(/\A\d{10}/, Nondisposable::Tld.version)
  end

  def test_snapshot_holds_only_wellformed_tlds
    # IANA publishes A-Z0-9 and hyphen, uppercase; we store it downcased. A
    # stray comment or a blank line leaking into the Set would be a silent
    # accept for garbage.
    assert_empty Nondisposable::Tld.all.reject { |tld| tld.match?(/\A[a-z0-9-]+\z/) }
  end

  def test_knows_the_common_ones_and_the_long_tail
    %w[com es org net io app dev gle xn--fiqs8s].each do |tld|
      assert Nondisposable::Tld.valid?(tld), ".#{tld} should be in the root zone"
    end
  end

  # =========================================================================
  # Extraction
  # =========================================================================

  def test_extracts_the_tld_from_an_address_or_a_bare_domain
    assert_equal "com", Nondisposable::Tld.extract("user@gmail.com")
    assert_equal "com", Nondisposable::Tld.extract("gmail.com")
    assert_equal "uk",  Nondisposable::Tld.extract("user@bbc.co.uk")
  end

  def test_extraction_is_case_and_whitespace_insensitive
    assert_equal "com", Nondisposable::Tld.extract("  USER@Gmail.COM  ")
  end

  def test_ignores_the_trailing_dot_of_a_fully_qualified_name
    # `gmail.com.` is the same host, root dot and all. Without the trim the last
    # label is "" and a perfectly good address looks TLD-less.
    assert_equal "com", Nondisposable::Tld.extract("user@gmail.com.")
    assert Nondisposable.valid_tld?("user@gmail.com.")
  end

  def test_a_dotless_domain_has_no_tld_at_all
    # This reproduces a production typo without retaining the customer's local
    # part. There is no TLD here to be valid, which is exactly why it fails.
    assert_nil Nondisposable::Tld.extract("example@gmailmcom")
    assert Nondisposable::Tld.judgeable?("example@gmailmcom")
    refute Nondisposable.valid_tld?("example@gmailmcom")
  end

  def test_ip_literals_are_left_alone
    # "What is the TLD" is the wrong question here, not a question with a bad
    # answer. Whether to accept IP-literal addresses is a format policy, and a
    # TLD check has no business deciding it.
    refute Nondisposable::Tld.judgeable?("user@192.168.0.1")
    refute Nondisposable::Tld.judgeable?("user@[10.0.0.1]")
    assert Nondisposable.valid_tld?("user@192.168.0.1")
    assert Nondisposable.valid_tld?("user@[10.0.0.1]")
  end

  # =========================================================================
  # Validity
  # =========================================================================

  def test_rejects_tlds_that_do_not_exist
    # Synthetic local parts reproduce the three shapes measured in production.
    refute Nondisposable.valid_tld?("example@gmail.con")
    refute Nondisposable.valid_tld?("example@outlook.ed")
    refute Nondisposable.valid_tld?("example@gmailmcom")
  end

  def test_accepts_the_lookalike_tlds_that_are_genuinely_real
    # .co, .cm and .om are Colombia, Cameroon and Oman. A TLD check must NOT
    # pretend otherwise — catching those typos is Suggestion's job, and this
    # test is here to stop anyone "fixing" it by blocklisting real countries.
    %w[gmail.co gmail.cm gmail.om].each do |domain|
      assert Nondisposable.valid_tld?("user@#{domain}"), "#{domain} is a real TLD"
    end
  end

  def test_unicode_tlds_are_never_rejected
    # IANA lists IDNs in punycode and we deliberately don't depend on an IDN
    # library to convert. A false accept is a nuisance; a false reject is a
    # locked-out human, so we decline to judge.
    assert Nondisposable.valid_tld?("user@例え.テスト")
    # The punycode form, which is what mail clients actually send, is checked.
    assert Nondisposable.valid_tld?("user@example.xn--fiqs8s")
    refute Nondisposable.valid_tld?("user@example.xn--nope-not-real")
  end

  def test_additional_tlds_accept_something_newer_than_the_snapshot
    # The escape hatch: a host must never be stuck waiting on a gem release
    # because ICANN delegated a TLD last week.
    refute Nondisposable.valid_tld?("user@example.brandnewtld")

    Nondisposable.configure { |c| c.additional_tlds = ["brandnewtld"] }
    assert Nondisposable.valid_tld?("user@example.brandnewtld")
  end

  def test_rfc_reserved_names_are_rejected_because_they_are_undeliverable
    # RFC 6761 / RFC 2606 reserve these so they can NEVER be delegated. That is
    # exactly why fixtures use them, and exactly why a signup form must refuse
    # them: mail could never arrive.
    Nondisposable::Tld::SPECIAL_USE.each do |tld|
      refute Nondisposable::Tld.valid?(tld), ".#{tld} is reserved, never delegated"
      refute Nondisposable::Tld.all.include?(tld), ".#{tld} must not be in the root zone snapshot"
    end
  end

  def test_special_use_is_the_one_line_fix_for_a_red_test_suite
    # The documented remedy, tested so the constant can't drift from the advice
    # in the README: config.additional_tlds = Tld::SPECIAL_USE if Rails.env.local?
    refute Nondisposable.valid_tld?("user@myapp.test")

    Nondisposable.configure { |c| c.additional_tlds = Nondisposable::Tld::SPECIAL_USE }

    assert Nondisposable.valid_tld?("user@myapp.test")
    assert Nondisposable.valid_tld?("user@myapp.example")
    # …and it doesn't quietly wave anything else through.
    refute Nondisposable.valid_tld?("user@myapp.con")
  end

  def test_configured_tlds_may_be_written_with_or_without_a_leading_dot
    Nondisposable.configure { |c| c.additional_tlds = [".BrandNewTld "] }
    assert Nondisposable.valid_tld?("user@example.brandnewtld")
  end

  # =========================================================================
  # Degenerate input — the guards, proven rather than assumed
  # =========================================================================

  def test_empty_and_missing_input_is_never_accidentally_valid
    # An empty TLD must not sail through as "nothing to check". These guards are
    # the difference between "we have no opinion" and "sure, looks fine".
    refute Nondisposable::Tld.valid?("")
    refute Nondisposable::Tld.valid?(nil)
    refute Nondisposable::Tld.blocked?("")
    refute Nondisposable::Tld.judgeable?("")
    refute Nondisposable::Tld.judgeable?(nil)
    assert_nil Nondisposable::Tld.extract("")
    assert_nil Nondisposable::Tld.extract("user@")
  end

  def test_a_domain_that_is_nothing_but_dots_has_no_tld
    assert_nil Nondisposable::Tld.extract("user@.")
    assert_nil Nondisposable::Tld.extract("user@..")
  end

  # =========================================================================
  # The snapshot is swappable, and reload! picks the swap up
  # =========================================================================

  def test_reload_reads_a_replaced_snapshot
    # This is what TldListUpdater relies on: rewriting the file is pointless if
    # the process keeps answering from the Set it built at boot.
    with_tld_list("# Version 9999\nZZTOP\n") do
      assert_equal ["zztop"], Nondisposable::Tld.all.to_a
      assert Nondisposable::Tld.valid?("zztop")
      refute Nondisposable::Tld.valid?("com")
      assert_equal "9999", Nondisposable::Tld.version
    end

    # …and the real snapshot is back afterwards.
    assert Nondisposable::Tld.valid?("com")
  end

  def test_a_snapshot_without_a_version_header_reports_no_version
    with_tld_list("COM\nES\n") do
      assert_nil Nondisposable::Tld.version
      assert_equal %w[com es].sort, Nondisposable::Tld.all.to_a.sort
    end
  end

  def test_comments_and_blank_lines_never_become_tlds
    with_tld_list("# Version 1\n\nCOM\n\n# a stray comment\nES\n") do
      assert_equal %w[com es].sort, Nondisposable::Tld.all.to_a.sort
    end
  end

  # Swaps the bundled snapshot for a fixture, then puts it back. Used instead of
  # stubbing so the parse, the memoisation and reload! are all exercised for
  # real — the same path TldListUpdater takes after it writes.
  def with_tld_list(contents)
    original = Nondisposable::Tld::LIST_PATH
    Dir.mktmpdir do |dir|
      path = File.join(dir, "iana_tlds.txt")
      File.write(path, contents)
      swap_tld_list_path(path)
      yield
    ensure
      swap_tld_list_path(original)
    end
  end

  def swap_tld_list_path(path)
    Nondisposable::Tld.send(:remove_const, :LIST_PATH)
    Nondisposable::Tld.const_set(:LIST_PATH, path)
    Nondisposable::Tld.reload!
  end

  # =========================================================================
  # Blocking and allowlisting
  # =========================================================================

  def test_blocked_tlds_refuse_a_real_tld
    assert Nondisposable.valid_tld?("user@example.tk")

    Nondisposable.configure { |c| c.blocked_tlds = %w[tk ml ga cf gq] }

    refute Nondisposable.valid_tld?("user@example.tk")
    assert Nondisposable.valid_tld?("user@example.com")
  end

  def test_allowed_tlds_turn_the_check_into_an_allowlist
    Nondisposable.configure { |c| c.allowed_tlds = %w[es com] }

    assert Nondisposable.valid_tld?("user@example.es")
    assert Nondisposable.valid_tld?("user@example.com")
    refute Nondisposable.valid_tld?("user@example.io")
  end

  def test_allowlist_and_blocklist_compose_with_the_blocklist_winning
    Nondisposable.configure do |c|
      c.allowed_tlds = %w[es com]
      c.blocked_tlds = %w[com]
    end

    assert Nondisposable.valid_tld?("user@example.es")
    refute Nondisposable.valid_tld?("user@example.com")
  end
end
