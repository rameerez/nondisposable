# frozen_string_literal: true

require "test_helper"

class NondisposableSourceTest < NondisposableTestCase
  S = Nondisposable::Source

  def source(**overrides)
    S.new(**{ name: "example", url: "https://example.com/list.txt" }.merge(overrides))
  end

  # =========================================================================
  # Descriptors
  # =========================================================================

  def test_defaults
    s = source
    assert_equal :corroborating, s.trust
    assert_equal [], s.derived_from
    assert_equal 1, s.minimum_count
    assert_equal S::DEFAULT_MAX_BYTES, s.max_bytes
    assert_equal S::DEFAULT_DEADLINE, s.deadline
    refute s.primary?
    assert s.frozen?
  end

  def test_build_accepts_a_source_or_a_hash_with_string_keys
    s = source
    assert_same s, S.build(s)

    built = S.build("name" => "mine", "url" => "https://example.com/x", "trust" => "primary", "derived_from" => "other")
    assert built.primary?
    assert_equal %w[other], built.derived_from
  end

  def test_build_rejects_anything_else
    assert_raises(ArgumentError) { S.build("https://example.com/list.txt") }
  end

  def test_validation_errors
    assert_raises(ArgumentError) { source(url: "http://example.com/list.txt") }
    assert_raises(ArgumentError) { source(trust: :gospel) }
    assert_raises(ArgumentError) { source(name: "Has Spaces") }
    assert_raises(ArgumentError) { source(max_bytes: 0) }
    assert_raises(ArgumentError) { source(minimum_count: 0) }
    assert_raises(ArgumentError) { source(deadline: 0) }
    assert_raises(ArgumentError) { source(deadline: "soon") }
    assert_raises(ArgumentError) { source(derived_from: %w[example]) }
  end

  def test_with_copies_and_overrides
    promoted = Nondisposable::Sources::DISPOSABLE.with(trust: :primary)
    assert promoted.primary?
    refute Nondisposable::Sources::DISPOSABLE.primary?
    assert_equal Nondisposable::Sources::DISPOSABLE.derived_from, promoted.derived_from
  end

  def test_value_equality
    assert_equal source, source
    assert_equal source.hash, source.hash
    refute_equal source, source(trust: :primary)
    refute_equal source, "example"
  end

  # =========================================================================
  # Presets
  # =========================================================================

  def test_default_preset_is_todays_single_list
    assert_equal [Nondisposable::Sources::DISPOSABLE_EMAIL_DOMAINS], Nondisposable::Sources::DEFAULT
    assert_equal Nondisposable::DomainListUpdater::LIST_URL, Nondisposable::Sources::DISPOSABLE_EMAIL_DOMAINS.url
    assert_equal Nondisposable::Sources::DEFAULT, Nondisposable.configuration.sources
  end

  def test_recommended_preset_is_two_independent_primaries
    recommended = Nondisposable::Sources::RECOMMENDED
    assert_equal %w[disposable-email-domains fakefilter], recommended.map(&:name)
    assert recommended.all?(&:primary?)
    assert recommended.none? { |s| (s.derived_from & recommended.map(&:name)).any? }
  end

  def test_every_preset_source_is_https_licensed_and_unique
    all = Nondisposable::Sources.constants.map { |c| Nondisposable::Sources.const_get(c) }.grep(S)
    assert_operator all.size, :>=, 6
    assert all.all? { |s| s.url.start_with?("https://raw.githubusercontent.com/") }
    assert all.all?(&:license)
    assert_equal all.size, all.map(&:name).uniq.size
  end

  def test_lineage_of_aggregators_is_declared
    assert_includes Nondisposable::Sources::DISPOSABLE.derived_from, "mailchecker"
    assert_includes Nondisposable::Sources::GROUNDCAT.derived_from, "disposable"
  end

  # =========================================================================
  # Parsing
  # =========================================================================

  def test_parse_normalizes_dedupes_and_sorts
    parsed = S.parse("B.com\r\na.com\n\n  a.com  \nA.COM.\n")
    assert_equal %w[a.com b.com], parsed.domains
    assert_equal 4, parsed.lines
    assert_equal 0, parsed.invalid
  end

  def test_parse_strips_whole_line_and_inline_comments
    # fakefilter groups its list under "## provider" headers.
    parsed = S.parse("# header\n## 10minutemail.info\nlaoia.com # inline\n")
    assert_equal %w[laoia.com], parsed.domains
    assert_equal 1, parsed.lines
  end

  def test_parse_counts_and_samples_junk
    parsed = S.parse("ok.com\n<html>\n<body>404</body>\n")
    assert_equal %w[ok.com], parsed.domains
    assert_equal 2, parsed.invalid
    assert_in_delta 2.0 / 3, parsed.invalid_ratio
    assert_equal ["<html>", "<body>404</body>"], parsed.invalid_sample
  end

  def test_parse_keeps_public_suffixes_for_the_snapshot_record
    assert_equal %w[com.br], S.parse("com.br\n").domains
  end

  def test_parse_converts_idns_to_punycode
    assert_equal %w[xn--bcher-kva.de], S.parse("bücher.de\n").domains
  end

  def test_parse_of_nothing
    parsed = S.parse(nil)
    assert_equal [], parsed.domains
    assert_equal 0.0, parsed.invalid_ratio
  end
end

class NondisposableSourceMergeTest < NondisposableTestCase
  def src(name, trust: :corroborating, derived_from: [])
    Nondisposable::Source.new(name: name, url: "https://example.com/#{name}", trust: trust, derived_from: derived_from)
  end

  def merge(snapshots, threshold: 2)
    Nondisposable::SourceMerge.call(snapshots, threshold: threshold)
  end

  def test_primaries_are_unioned
    result = merge({ src("a", trust: :primary) => %w[x.com], src("b", trust: :primary) => %w[y.com] })
    assert_equal Set["x.com", "y.com"], result.domains
    assert_equal 2, result.primary_count
    assert_equal 0, result.corroborated_count
  end

  def test_a_single_corroborating_vote_is_not_enough
    result = merge({ src("p", trust: :primary) => %w[p.com], src("c1") => %w[only-one.com] })
    refute_includes result.domains, "only-one.com"
  end

  def test_two_independent_corroborating_origins_block
    result = merge({ src("p", trust: :primary) => [], src("c1") => %w[both.com], src("c2") => %w[both.com] })
    assert_includes result.domains, "both.com"
    assert_equal 1, result.corroborated_count
  end

  def test_a_copy_does_not_count_as_a_second_origin
    # mail-burn.com on 2026-10-17: disposable/disposable crawled it, groundcat
    # copied it from there. One observation, not two.
    snapshots = {
      src("disposable") => %w[mail-burn.com],
      src("groundcat", derived_from: %w[disposable]) => %w[mail-burn.com]
    }
    refute_includes merge(snapshots).domains, "mail-burn.com"
    assert_equal %w[disposable], Nondisposable::SourceMerge.origins_for("mail-burn.com", snapshots)
  end

  def test_lineage_is_transitive
    snapshots = {
      src("mailchecker") => %w[x.com],
      src("disposable", derived_from: %w[mailchecker]) => %w[x.com],
      src("groundcat", derived_from: %w[disposable]) => %w[x.com]
    }
    assert_equal %w[mailchecker], Nondisposable::SourceMerge.origins_for("x.com", snapshots)
    refute_includes merge(snapshots).domains, "x.com"
  end

  def test_an_upstream_that_was_not_loaded_explains_nothing
    snapshots = { src("groundcat", derived_from: %w[ivolo]) => %w[x.com], src("wesbos") => %w[x.com] }
    assert_includes merge(snapshots).domains, "x.com"
  end

  def test_a_downstream_entry_missing_from_its_upstream_is_its_own_observation
    snapshots = {
      src("mailchecker") => %w[other.com],
      src("disposable", derived_from: %w[mailchecker]) => %w[crawled.com],
      src("wesbos") => %w[crawled.com]
    }
    assert_includes merge(snapshots).domains, "crawled.com"
  end

  def test_threshold_one_trusts_any_corroborating_source
    assert_includes merge({ src("c1") => %w[x.com] }, threshold: 1).domains, "x.com"
  end

  def test_threshold_must_be_positive
    assert_raises(ArgumentError) { merge({}, threshold: 0) }
  end
end
