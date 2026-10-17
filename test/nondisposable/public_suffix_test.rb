# frozen_string_literal: true

require "test_helper"

# The public-suffix guard: no single list entry may block a whole namespace.
# (Nondisposable::Domain is tested in domain_test.rb, with the lookalike work.)
class NondisposablePublicSuffixTest < NondisposableTestCase
  PS = Nondisposable::PublicSuffix

  def test_icann_suffixes_are_public
    %w[com es co.uk com.br com.es com.mx ac.jp].each do |suffix|
      assert PS.public_suffix?(suffix), "#{suffix} should be a public suffix"
    end
  end

  def test_private_section_suffixes_are_public
    %w[github.io blogspot.com ddns.net].each do |suffix|
      assert PS.public_suffix?(suffix), "#{suffix} should be a public suffix"
    end
  end

  def test_registrable_domains_are_not
    %w[gmail.com tempmail.com bbc.co.uk upm.es alumnos.upm.es username.github.io].each do |domain|
      refute PS.public_suffix?(domain), "#{domain} should not be a public suffix"
    end
  end

  def test_single_labels_are_always_public_even_unknown_ones
    assert PS.public_suffix?("com")
    assert PS.public_suffix?("notarealtld")
  end

  def test_wildcard_and_exception_rules
    # From the list itself: `*.ck` and `!www.ck`.
    assert PS.public_suffix?("anything.ck")
    refute PS.public_suffix?("www.ck")
    refute PS.public_suffix?("example.anything.ck")
  end

  def test_unicode_rules_match_their_punycode_form
    assert PS.public_suffix?("xn--p1ai") # рф
    assert PS.public_suffix?(Nondisposable::Domain.normalize("рф"))
  end

  def test_empty_is_not_a_suffix
    refute PS.public_suffix?("")
    refute PS.public_suffix?(nil)
  end

  def test_parse_handles_comments_whitespace_and_rule_kinds
    rules = PS.parse("// comment\n\nfoo\n*.bar\n!baz.bar\nqux trailing words\n")

    assert_equal Set["foo", "qux"], rules[:exact]
    assert_equal Set["bar"], rules[:wildcards]
    assert_equal Set["baz.bar"], rules[:exceptions]
  end

  def test_snapshot_ships_with_version_and_thousands_of_rules
    assert File.exist?(PS::LIST_PATH)
    assert_operator PS.rule_count, :>, 5_000
    assert_match(/\A\d{4}-\d{2}-\d{2}/, PS.version)
  end

  def test_reload_clears_memoized_rules
    PS.public_suffix?("com")
    assert_same PS, PS.reload!
    assert PS.public_suffix?("co.uk")
  end

  def test_version_is_nil_when_the_file_is_unreadable
    PS.reload!
    File.stub(:foreach, proc { raise Errno::ENOENT }) do
      assert_nil PS.version
    end
  ensure
    PS.reload!
  end
end
