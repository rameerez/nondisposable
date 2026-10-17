# frozen_string_literal: true

require "test_helper"

# Regressions for the PR #6 codex review, round 2
# (docs/reviews/2026-10-17-pr6-codex-round2.md). Each test names its finding.
class NondisposableReviewRound2Test < NondisposableTestCase
  Updater = Nondisposable::DomainListUpdater
  Snapshot = Nondisposable::SourceSnapshot

  def setup
    super
    create_snapshots_table!
  end

  def teardown
    drop_snapshots_table!
    super
  end

  def src(name, trust: :primary, derived_from: [])
    Nondisposable::Source.new(name: name, url: "https://lists.example/#{name}.txt", trust: trust, derived_from: derived_from)
  end

  def stub_source(source, body, status: 200)
    stub_request(:get, source.url).to_return(status: status, body: body)
  end

  def list(*domains)
    domains.flatten.join("\n") + "\n"
  end

  def many(count, prefix: "d")
    (1..count).map { |i| "#{prefix}#{i}.com" }
  end

  def stored?(name)
    Nondisposable::DisposableDomain.exists?(name: name)
  end

  # R1-2: rolling back a SOLE primary's only snapshot, over a populated table.
  def test_rollback_of_a_sole_primarys_only_snapshot_falls_back_to_the_bundled_list
    a = src("a")
    Nondisposable.configuration.sources = [a]
    stub_source(a, list("victim-employer.com", "temp.com"))
    assert Updater.update
    assert stored?("victim-employer.com")

    log = capture_log { assert Updater.rollback("a") }

    assert_includes log, "publishing the list bundled with the gem in its place"
    refute stored?("victim-employer.com")
    assert stored?("mailinator.com")
  end

  # R1-5: padding with entries the filter drops (relays here) cannot pass for
  # a full list.
  def test_relay_padding_cannot_replace_the_seed
    Updater.seed
    seeded = Nondisposable::DisposableDomain.count
    padding = (1..6_000).map { |i| "x#{i}.anonaddy.com" }
    stub_source(Nondisposable::Sources::DISPOSABLE_EMAIL_DOMAINS, list(padding, "victim-employer.com"))

    log = capture_log { refute Updater.update }

    assert_includes log, "Refusing the new disposable-email-domains list: only 1 domains"
    assert_equal seeded, Nondisposable::DisposableDomain.count
    refute stored?("victim-employer.com")
  end

  # R1-6: accepted cuts beyond retention cannot erase the baseline.
  def test_accepted_cuts_cannot_ratchet_past_the_high_water_mark
    a = src("a")
    Nondisposable.configuration.sources = [a]
    [100, 60, 59, 58, 57, 56].each do |n|
      stub_source(a, list(many(n)))
      assert Updater.update, "#{n} should be accepted"
    end

    stub_source(a, list(many(30)))
    log = capture_log { refute Updater.update }
    assert_includes log, "shrank to 30 domains from 100"
    assert_equal 100, Snapshot.last_good("a").high_water_count
  end

  def test_a_human_can_reset_the_baseline
    a = src("a")
    Nondisposable.configuration.sources = [a]
    stub_source(a, list(many(100)))
    assert Updater.update
    stub_source(a, list(many(60)))
    assert Updater.update

    assert Updater.reset_baseline("a")
    stub_source(a, list(many(31)))
    assert Updater.update
    refute Updater.reset_baseline("nope")
  end

  # R1-8: lineage through a configured source that has no snapshot.
  def test_lineage_through_a_failed_middle_source_still_correlates
    root_mirror = src("a", trust: :corroborating, derived_from: %w[root])
    middle = src("mid", trust: :corroborating, derived_from: %w[root])
    downstream = src("b", trust: :corroborating, derived_from: %w[mid])
    p = src("p")
    Nondisposable.configuration.sources = [p, root_mirror, middle, downstream]
    stub_source(p, list("p.com"))
    stub_source(root_mirror, list("victim-employer.com"))
    stub_source(middle, "", status: 500)
    stub_source(downstream, list("victim-employer.com"))

    refute Updater.update
    refute stored?("victim-employer.com"), "a and b share root through mid, even though mid failed"
  end

  # #13: the rollback target is chosen inside the lock.
  def test_rollback_withdraws_the_snapshot_that_is_newest_when_it_runs
    a = src("a")
    Nondisposable.configuration.sources = [a]
    stub_source(a, list("good.com"))
    assert Updater.update
    stub_source(a, list("good.com", "victim-employer.com"))
    assert Updater.update
    poisoned = Snapshot.last_good("a")

    # A refresh that lands just before the rollback takes the lock: same poison
    # plus one more line, so a different snapshot.
    racing = Snapshot.create!(source: "a", status: "ok", fetched_at: Time.current + 1, domain_count: 3,
                              domains: "good.com\nother.com\nvictim-employer.com", sha256: "racing")

    assert Updater.rollback("a")
    assert_equal "rolled_back", racing.reload.status
    assert_equal "ok", poisoned.reload.status
    assert_equal poisoned, Snapshot.last_good("a")
  end

  # #14: an unchanged refresh never moves a snapshot back in time.
  def test_unchanged_refresh_never_lowers_snapshot_ordering
    a = src("a")
    Nondisposable.configuration.sources = [a]
    stub_source(a, list("clean.com"))
    assert Updater.update
    clean = Snapshot.last_good("a")
    later = clean.fetched_at + 60
    clean.update!(fetched_at: later)

    stub_source(a, list("clean.com"))
    travel_back = clean.fetched_at - 120
    Time.stub(:current, travel_back) { assert Updater.update }

    assert_equal later.to_i, clean.reload.fetched_at.to_i
  end

  # #15: oversized input costs nothing.
  def test_oversized_ascii_input_is_refused_quickly
    setup_disposable_domain!("tempmail.com")
    huge = (["a"] * 4_000).join(".") + ".tempmail.com"
    huge_labels = ("x" * 8_000) + ".tempmail.com"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Over-length is junk: TRUE (lead decision 2026-10-17), and cheap.
    assert Nondisposable::DisposableDomain.disposable?(huge)
    assert Nondisposable::DisposableDomain.disposable?(huge_labels)
    assert Nondisposable.disposable?("user@#{huge}")
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
  end

  # #16: many correlated mirrors stay fast.
  def test_correlated_mirrors_do_not_explode
    mirrors = (1..14).map { |i| src("m#{i}", trust: :corroborating, derived_from: %w[root]) }
    snapshots = mirrors.to_h { |m| [m, many(1_000, prefix: "s")] }
    snapshots[src("p")] = %w[p.com]

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Nondisposable::SourceMerge.call(snapshots, threshold: 2)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.0
    assert_equal 0, result.corroborated_count, "14 mirrors of one root are one origin"
  end

  # R1-10: an oversized unicode label skips punycode and stays cheap.
  def test_oversized_unicode_label_is_cheap
    label = (0x4E00...(0x4E00 + 4_000)).map { |cp| [cp].pack("U") }.join
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert Nondisposable.disposable?("user@#{label}.com")
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
  end

  # R1-12: full-width input is the same domain as its ASCII form.
  def test_fullwidth_input_matches_the_ascii_listing
    setup_disposable_domain!("tempmail.com")
    assert Nondisposable.disposable?("user@ｔｅｍｐｍａｉｌ.com")
  end
  # Carried over from PR #5 (its round-2 #5): rows a 0.4.0 table stored in
  # unicode still block, and exclusions still apply to them.
  def test_legacy_unicode_rows_still_block
    Nondisposable::DisposableDomain.insert_all([{ name: "bücher.de" }], record_timestamps: true)

    assert Nondisposable::DisposableDomain.disposable?("bücher.de")
    assert Nondisposable::DisposableDomain.disposable?("x.Bücher.de")
    refute Nondisposable::DisposableDomain.disposable?("xn--bcher-kva.de"), "only a unicode address can match a unicode row"

    Nondisposable.configuration.excluded_domains = ["xn--bcher-kva.de"]
    refute Nondisposable::DisposableDomain.disposable?("bücher.de")
  end

  def test_non_utf8_domains_are_never_disposable
    setup_disposable_domain!("tempmail.com")
    refute Nondisposable::DisposableDomain.disposable?("\xFF\xFE.tempmail.com".b)
  end
  # ---- Round 3 (docs/reviews/2026-10-17-pr6-codex-round3.md) -------------

  # R3-3: invisible padding past 1,024 raw characters still normalizes to a
  # listed domain, and is still blocked.
  def test_soft_hyphen_padding_cannot_hide_a_listed_domain
    setup_disposable_domain!("tempmail.com")
    padded = ("­" * 1013) + "tempmail.com"
    assert_operator padded.length, :>, 1_024
    assert Nondisposable::DisposableDomain.disposable?(padded)
    assert Nondisposable.disposable?("user@#{padded}")
  end

  # Lead decision 2026-10-17: a name longer than DNS allows can never be
  # deliverable, so direct callers get TRUE, never "fine". Names exactly at
  # the limits are judged normally.
  def test_names_longer_than_dns_allows_are_disposable
    too_long_total = ((["a" * 50] * 5).join(".")) + ".example.com" # > 253
    too_long_label = ("b" * 64) + ".example.com"

    assert Nondisposable::DisposableDomain.disposable?(too_long_total)
    assert Nondisposable::DisposableDomain.disposable?(too_long_label)
    assert Nondisposable.disposable?("user@#{too_long_label}")

    at_label_limit = ("c" * 63) + ".example.com"
    at_total_limit = ((["d" * 62] * 3).join(".")) + "." + ("e" * (253 - 3 * 63 - 4)) + ".com"
    assert_equal 253, at_total_limit.length
    refute Nondisposable::DisposableDomain.disposable?(at_label_limit)
    refute Nondisposable::DisposableDomain.disposable?(at_total_limit)
  end

  # The lead's exact cases, through both entry points.
  def test_lead_cases_for_over_length_names
    ["a" * 64 + ".com", "a." * 130 + "com"].each do |name|
      assert Nondisposable::DisposableDomain.disposable?(name), name[0, 20]
      assert Nondisposable.disposable?("user@#{name}"), name[0, 20]
    end
    ["a" * 63 + ".com", "a." * 125 + "com"].each do |name| # 63-char label; 253 chars
      refute Nondisposable::DisposableDomain.disposable?(name), name[0, 20]
      refute Nondisposable.disposable?("user@#{name}"), name[0, 20]
    end
  end

  # R3-4: a block_privacy_relays flip compares like with like, and a reset
  # recomputes from the payload.
  def test_a_relay_policy_flip_does_not_trip_the_shrink_guard
    a = src("a")
    Nondisposable.configuration.sources = [a]
    Nondisposable.configuration.block_privacy_relays = true
    body = list((1..100).map { |i| "x#{i}.anonaddy.com" }, many(20))
    stub_source(a, body)
    assert Updater.update

    Nondisposable.configuration.block_privacy_relays = false
    stub_source(a, body)
    assert Updater.update, "the same payload under the other policy is the same size"

    assert Updater.reset_baseline("a")
    assert_equal 20, Snapshot.last_good("a").high_water_count
    stub_source(a, list((1..100).map { |i| "x#{i}.anonaddy.com" }, many(20), "extra.com"))
    assert Updater.update
  end

  def test_reset_baseline_recomputes_from_the_payload
    a = src("a")
    Nondisposable.configuration.sources = [a]
    stub_source(a, list(many(10)))
    assert Updater.update
    Snapshot.last_good("a").update!(domain_count: 999, high_water_count: 999) # a stale figure

    assert Updater.reset_baseline("a")
    assert_equal 10, Snapshot.last_good("a").high_water_count
  end

  # R3-1: a snapshots table from an earlier build without high_water_count
  # never crashes a refresh.
  def test_a_table_without_high_water_count_still_refreshes
    ActiveRecord::Base.connection.remove_column(:nondisposable_source_snapshots, :high_water_count)
    Snapshot.reset_column_information
    Updater.instance_variable_set(:@warned_high_water, nil)
    a = src("a")
    Nondisposable.configuration.sources = [a]

    stub_source(a, list(many(100)))
    log = capture_log { assert Updater.update }
    assert_includes log, "has no high_water_count column"

    stub_source(a, list(many(40)))
    log = capture_log { refute Updater.update }
    assert_includes log, "shrank to 40 domains from 100", "falls back to retained snapshots"

    assert Updater.reset_baseline("a")
  ensure
    Updater.instance_variable_set(:@warned_high_water, nil)
  end
end
