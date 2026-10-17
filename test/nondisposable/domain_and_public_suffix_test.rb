# frozen_string_literal: true

require "test_helper"

# Canonicalization and the public-suffix guard: the two things every list and
# every check must agree on before any precedence rule means anything.
class NondisposableDomainTest < NondisposableTestCase
  D = Nondisposable::Domain

  def test_downcases_strips_and_drops_the_trailing_dot
    assert_equal "tempmail.com", D.normalize("  TempMail.COM. \r\n")
  end

  def test_blank_input_is_an_empty_string
    assert_equal "", D.normalize(nil)
    assert_equal "", D.normalize("   ")
    assert_equal "", D.normalize(".")
  end

  def test_ascii_input_is_otherwise_untouched
    assert_equal "xn--bcher-kva.de", D.normalize("xn--bcher-kva.de")
    assert_equal "a_b-c.example.com", D.normalize("A_B-C.example.com")
  end

  def test_unicode_and_punycode_forms_are_the_same_domain
    assert_equal D.normalize("xn--bcher-kva.de"), D.normalize("bücher.de")
    assert_equal D.normalize("xn--bcher-kva.de"), D.normalize("BÜCHER.de")
  end

  # RFC 3492 §7.1 sample strings, plus everyday IDNs.
  def test_punycode_matches_published_vectors
    assert_equal "xn--mnchen-3ya.de", D.normalize("münchen.de")
    assert_equal "xn--r8jz45g.xn--zckzah", D.normalize("例え.テスト")
    assert_equal "xn--egbpdaj6bu4bxfgehfvwxn", D.normalize("ليهمابتكلموشعربي؟")
    assert_equal "xn--ihqwcrb4cv8a8dqg056pqjye", D.normalize("他们为什么不说中文")
    assert_equal "xn--maana-pta.com", D.normalize("mañana.com")
  end

  def test_nfkc_folds_compatibility_characters
    # Full-width Latin letters are what an IME produces; they are the same
    # domain as their ASCII forms.
    assert_equal "gmail.com", D.normalize("ｇｍａｉｌ.com")
  end

  def test_never_raises_on_odd_input
    assert_kind_of String, D.normalize("\xFF\xFE.com".dup.force_encoding("BINARY"))
    assert_kind_of String, D.normalize(12345)
  end
end

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
