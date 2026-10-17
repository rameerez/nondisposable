# frozen_string_literal: true

require "test_helper"

# DomainListUpdater with the nondisposable_source_snapshots table present: the
# multi-source path. (domain_list_updater_test.rb covers the single-source
# path that hosts without the table keep.)
class NondisposableMultiSourceUpdaterTest < NondisposableTestCase
  Updater = Nondisposable::DomainListUpdater
  Snapshot = Nondisposable::SourceSnapshot
  DED = Nondisposable::Sources::DISPOSABLE_EMAIL_DOMAINS

  def setup
    super
    create_snapshots_table!
  end

  def teardown
    drop_snapshots_table!
    super
  end

  def src(name, trust: :primary, derived_from: [], minimum_count: 1)
    Nondisposable::Source.new(name: name, url: "https://lists.example/#{name}.txt", trust: trust,
                              derived_from: derived_from, minimum_count: minimum_count)
  end

  def use_sources(*sources)
    Nondisposable.configuration.sources = sources
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

  def stored
    Nondisposable::DisposableDomain.order(:name).pluck(:name)
  end

  # =========================================================================
  # Schema detection
  # =========================================================================

  def test_snapshots_table_is_detected
    assert Snapshot.available?
    drop_snapshots_table!
    refute Snapshot.available?
  end

  # =========================================================================
  # Default configuration: one source, same result as before
  # =========================================================================

  def test_default_source_publishes_and_records_a_snapshot
    body = list(many(5_000), "mailinator.com")
    stub_source(DED, body)

    assert Updater.update

    assert_equal 5_001, Nondisposable::DisposableDomain.count
    snapshot = Snapshot.last_good(DED.name)
    assert_equal 5_001, snapshot.domain_count
    assert_equal DED.url, snapshot.url
    assert_equal 64, snapshot.sha256.length
    assert_includes snapshot.domain_list, "mailinator.com"
  end

  def test_default_source_is_measured_against_the_bundled_seed
    # The bundled list holds ~8,000 domains, so a 1,500-domain response is a
    # truncation, not an upstream decision.
    Updater.seed
    seeded = Nondisposable::DisposableDomain.count
    stub_source(DED, list(many(1_500)))

    log = capture_log { refute Updater.update }

    assert_includes log, "shrank"
    assert_equal seeded, Nondisposable::DisposableDomain.count
    assert_equal "rejected", Snapshot.newest_first.first.status
  end

  # =========================================================================
  # Several sources
  # =========================================================================

  def test_primaries_are_merged
    a = src("a")
    b = src("b")
    use_sources(a, b)
    stub_source(a, list("one.com", "shared.com"))
    stub_source(b, list("two.com", "shared.com"))

    assert Updater.update
    assert_equal %w[one.com shared.com two.com], stored
  end

  def test_corroborating_sources_need_independent_origins
    p = src("p")
    c1 = src("c1", trust: :corroborating)
    c2 = src("c2", trust: :corroborating)
    copy = src("copy", trust: :corroborating, derived_from: %w[c1])
    use_sources(p, c1, c2, copy)
    stub_source(p, list("primary.com"))
    stub_source(c1, list("agreed.com", "copied.com", "lonely.com"))
    stub_source(c2, list("agreed.com"))
    stub_source(copy, list("copied.com"))

    assert Updater.update
    assert_equal %w[agreed.com primary.com], stored
  end

  def test_corroboration_threshold_is_configurable
    p = src("p")
    c1 = src("c1", trust: :corroborating)
    use_sources(p, c1)
    Nondisposable.configuration.corroboration_threshold = 1
    stub_source(p, list("primary.com"))
    stub_source(c1, list("single.com"))

    assert Updater.update
    assert_includes stored, "single.com"
  end

  # =========================================================================
  # Partial failure
  # =========================================================================

  def test_a_failing_source_falls_back_to_its_last_good_snapshot
    a = src("a")
    b = src("b")
    use_sources(a, b)
    stub_source(a, list("a1.com"))
    stub_source(b, list("b1.com"))
    assert Updater.update

    stub_source(a, list("a2.com"))
    stub_source(b, "", status: 500)
    refute Updater.update, "a failed source makes the run report false"

    assert_equal %w[a2.com b1.com], stored, "b's last good list stays in"
    failed = Snapshot.where(source: "b", status: "failed").first
    assert_includes failed.error, "500"
  end

  def test_first_run_with_a_failing_bundled_primary_stands_in_the_bundled_list
    use_sources(DED, src("other"))
    stub_source(DED, "", status: 503)
    stub_source(src("other"), list("other.com"))

    log = capture_log { refute Updater.update }

    assert_includes log, "using the list bundled with the gem in its place"
    assert Nondisposable::DisposableDomain.exists?(name: "mailinator.com"), "the seed's domains are all still there"
    assert Nondisposable::DisposableDomain.exists?(name: "other.com")
  end

  def test_first_run_with_a_never_fetched_primary_seeds_an_empty_table
    a = src("a")
    use_sources(a)
    stub_source(a, "", status: 500)

    log = capture_log { refute Updater.update }
    assert_includes log, "Not publishing"
    assert Nondisposable::DisposableDomain.exists?(name: "mailinator.com")
  end

  def test_first_run_with_a_failing_primary_keeps_an_existing_table
    setup_disposable_domain!("existing.com")
    a = src("a")
    use_sources(a)
    stub_source(a, "", status: 500)

    refute Updater.update
    assert_equal %w[existing.com], stored
  end

  def test_corroborating_source_without_a_snapshot_is_skipped
    p = src("p")
    c = src("c", trust: :corroborating)
    use_sources(p, c)
    stub_source(p, list("p.com"))
    stub_request(:get, c.url).to_raise(SocketError.new("no network"))

    log = capture_log { refute Updater.update }
    assert_includes log, "c has no good snapshot yet"
    assert_equal %w[p.com], stored
  end

  def test_network_errors_never_escape
    a = src("a")
    use_sources(a)
    stub_request(:get, a.url).to_raise(Net::ReadTimeout)
    refute Updater.update
  end

  # =========================================================================
  # Guards
  # =========================================================================

  def test_html_error_page_is_refused
    a = src("a")
    use_sources(a)
    stub_source(a, list("good.com"))
    assert Updater.update

    stub_source(a, "<html>\n<head><title>Rate limited</title></head>\nfine.com\n</html>\n")
    log = capture_log { refute Updater.update }

    assert_includes log, "not domain names"
    assert_equal %w[good.com], stored
  end

  def test_empty_list_is_refused
    a = src("a")
    use_sources(a)
    stub_source(a, "# nothing here\n")
    log = capture_log { refute Updater.update }
    assert_includes log, "the list is empty"
  end

  def test_minimum_count_is_enforced
    a = src("a", minimum_count: 3)
    use_sources(a)
    stub_source(a, list("one.com", "two.com"))
    log = capture_log { refute Updater.update }
    assert_includes log, "minimum_count is 3"
  end

  def test_sudden_shrink_is_refused
    a = src("a")
    use_sources(a)
    stub_source(a, list(many(100)))
    assert Updater.update

    stub_source(a, list(many(40)))
    log = capture_log { refute Updater.update }
    assert_includes log, "shrank to 40 domains from 100"
    assert_equal 100, Nondisposable::DisposableDomain.count
  end

  def test_repeated_shrinks_cannot_ratchet_the_list_down
    a = src("a")
    use_sources(a)
    stub_source(a, list(many(100)))
    assert Updater.update
    stub_source(a, list(many(60)))
    assert Updater.update, "a 40% cut is allowed once"

    stub_source(a, list(many(36)))
    log = capture_log { refute Updater.update }
    assert_includes log, "from 100", "measured against the largest retained snapshot, not the last one"
  end

  def test_failures_cannot_prune_away_the_shrink_baseline
    a = src("a")
    use_sources(a)
    stub_source(a, list(many(100)))
    assert Updater.update
    stub_source(a, list(many(60)))
    assert Updater.update
    stub_source(a, "", status: 500)
    (Snapshot::RETAINED_PER_SOURCE + 2).times { Updater.update }

    stub_source(a, list(many(36)))
    log = capture_log { refute Updater.update }
    assert_includes log, "from 100"
  end

  def test_sudden_growth_is_refused
    a = src("a")
    use_sources(a)
    stub_source(a, list(many(10)))
    assert Updater.update

    stub_source(a, list(many(31)))
    log = capture_log { refute Updater.update }
    assert_includes log, "grew to 31 domains from 10"
  end

  def test_unchanged_list_only_touches_the_snapshot
    a = src("a")
    use_sources(a)
    stub_source(a, list("x.com", "y.com"))
    assert Updater.update
    first = Snapshot.last_good("a")

    stub_source(a, list("Y.com", "x.com", "x.com"))
    log = capture_log { assert Updater.update }

    assert_includes log, "unchanged"
    assert_equal 1, Snapshot.where(source: "a").count
    assert_operator Snapshot.last_good("a").fetched_at, :>=, first.fetched_at
  end

  def test_changes_are_diffed_in_the_log
    a = src("a")
    use_sources(a)
    stub_source(a, list("keep.com", "gone.com"))
    assert Updater.update

    stub_source(a, list("keep.com", "new.com"))
    log = capture_log { assert Updater.update }

    assert_includes log, "a: 2 domains (+1 -1)"
    assert_includes log, "a added: new.com"
    assert_includes log, "a removed: gone.com"
    assert_includes log, "Total domains: 2 (+1 -1)"
  end

  # =========================================================================
  # Poisoning
  # =========================================================================

  def test_never_disposable_domains_in_a_source_are_dropped_and_reported
    a = src("a")
    use_sources(a)
    stub_source(a, list("temp.com", "gmail.com", "bak.rr.com", "sify.com"))

    log = capture_log { assert Updater.update }

    assert_equal %w[temp.com], stored
    assert_match(/a lists 3 domain\(s\) known to be real providers/, log)
    assert_equal 1, Snapshot.last_good("a").domain_count, "counts are of STORABLE domains"
    assert_equal 4, Snapshot.last_good("a").domain_list.size, "the list records what the source said"
  end

  def test_public_suffixes_in_a_source_are_dropped_and_reported
    a = src("a")
    use_sources(a)
    stub_source(a, list("temp.com", "com.br", "it.com"))

    log = capture_log { assert Updater.update }

    assert_equal %w[temp.com], stored
    assert_includes log, "a lists 2 public suffix(es)"
    refute Nondisposable.disposable?("rh@empresa.com.br")
  end

  def test_a_list_of_nothing_but_poison_is_never_published
    setup_disposable_domain!("existing.com")
    a = src("a")
    use_sources(a)
    stub_source(a, list("gmail.com", "outlook.com"))

    log = capture_log { refute Updater.update }
    assert_includes log, "the list is empty", "real providers do not count towards a list's size"
    assert_equal %w[existing.com], stored
  end

  def test_a_payload_padded_with_public_suffixes_cannot_replace_the_seed
    # codex: 6,000 suffix-shaped lines plus one employer used to pass every
    # size guard against the 8,000-domain seed and publish just the employer.
    Updater.seed
    seeded = Nondisposable::DisposableDomain.count
    padding = (1..6_000).map { |i| "x#{i}.sch.uk" } # each is a suffix via *.sch.uk
    stub_source(DED, list(padding, "victim-employer.com"))

    log = capture_log { refute Updater.update }
    assert_includes log, "Refusing the new disposable-email-domains list"
    assert_equal seeded, Nondisposable::DisposableDomain.count
    refute Nondisposable::DisposableDomain.exists?(name: "victim-employer.com")
  end

  def test_a_publish_that_empties_out_on_an_empty_table_still_seeds
    a = src("a")
    use_sources(a)
    Snapshot.create!(source: "a", status: "ok", fetched_at: Time.current, domain_count: 1, domains: "gmail.com")

    log = capture_log { refute Updater.publish }
    assert_includes log, "Refusing to publish an empty list"
    assert Nondisposable::DisposableDomain.exists?(name: "mailinator.com")
  end

  # =========================================================================
  # Host configuration goes through the same table
  # =========================================================================

  def test_host_lists_are_applied_when_publishing
    a = src("a")
    use_sources(a)
    Nondisposable.configuration.additional_domains = ["mail-burn.com", "gmail.com", "co.uk"]
    Nondisposable.configuration.excluded_domains = ["fine.com"]
    stub_source(a, list("temp.com", "fine.com", "duck.com"))

    log = capture_log { assert Updater.update }

    assert_equal %w[mail-burn.com temp.com], stored
    assert_match(/WARN.*additional_domain_is_never_disposable.*gmail\.com/, log)
    assert_match(/WARN.*invalid_additional_domain.*co\.uk/, log)
  end

  def test_publish_reapplies_configuration_without_fetching
    a = src("a")
    use_sources(a)
    stub_source(a, list("temp.com", "other.com"))
    assert Updater.update
    WebMock.reset!

    Nondisposable.configuration.excluded_domains = ["other.com"]
    assert Updater.publish
    assert_equal %w[temp.com], stored
  end

  def test_relays_can_be_stored_when_the_host_blocks_them
    a = src("a")
    use_sources(a)
    Nondisposable.configuration.block_privacy_relays = true
    stub_source(a, list("temp.com", "duck.com"))

    assert Updater.update
    assert_equal %w[duck.com temp.com], stored
  end

  # =========================================================================
  # Rollback and retention
  # =========================================================================

  def test_rollback_restores_the_previous_snapshot_and_refuses_the_payload_again
    a = src("a")
    use_sources(a)
    stub_source(a, list("good.com"))
    assert Updater.update
    stub_source(a, list("good.com", "victim-employer.com"))
    assert Updater.update
    assert_includes stored, "victim-employer.com"

    assert Updater.rollback("a")
    assert_equal %w[good.com], stored

    log = capture_log { refute Updater.update }
    assert_includes log, "identical to a snapshot that was rolled back"
    assert_equal %w[good.com], stored
  end

  def test_rolling_back_a_primarys_only_snapshot_withdraws_its_list
    a = src("a")
    b = src("b")
    use_sources(a, b)
    stub_source(a, list("a.com"))
    stub_source(b, list("b.com", "victim-employer.com"))
    assert Updater.update

    assert Updater.rollback("b")
    assert_equal %w[a.com], stored, "a poisoned primary must not stay published"
  end

  def test_rollback_quarantine_survives_pruning
    a = src("a")
    use_sources(a)
    stub_source(a, list("good.com"))
    assert Updater.update
    stub_source(a, list("good.com", "victim-employer.com"))
    assert Updater.update
    assert Updater.rollback("a")

    stub_source(a, "", status: 500)
    (Snapshot::RETAINED_PER_SOURCE + 2).times { Updater.update }

    stub_source(a, list("good.com", "victim-employer.com"))
    log = capture_log { refute Updater.update }
    assert_includes log, "identical to a snapshot that was rolled back"
  end

  def test_rollback_without_a_snapshot
    log = capture_log { refute Updater.rollback("nope") }
    assert_includes log, "Nothing to roll back"
  end

  def test_old_snapshots_are_pruned_but_the_last_good_one_survives
    a = src("a")
    use_sources(a)
    stub_source(a, list("good.com"))
    assert Updater.update
    good_id = Snapshot.last_good("a").id

    stub_source(a, "", status: 500)
    (Snapshot::RETAINED_PER_SOURCE + 3).times { Updater.update }

    rows = Snapshot.where(source: "a")
    assert_equal Snapshot::RETAINED_PER_SOURCE + 1, rows.count
    assert rows.exists?(id: good_id)
    assert_equal %w[good.com], stored
  end

  # =========================================================================
  # Configuration errors fail loudly, never silently shrink the list
  # =========================================================================

  def test_invalid_source_configurations
    [
      [],
      [src("a"), src("a")],
      [src("a"), Nondisposable::Source.new(name: "b", url: src("a").url, trust: :primary)],
      [src("only", trust: :corroborating)],
      [{ name: "x", url: "http://insecure.example/list" }]
    ].each do |sources|
      reset_configuration!
      Nondisposable.configuration.sources = sources
      log = capture_log { refute Updater.update }
      assert_includes log, "ArgumentError", "#{sources.inspect} should be refused"
    end
    assert Nondisposable::DisposableDomain.exists?(name: "mailinator.com"), "an empty table is still seeded"
  end

  def test_sources_may_be_given_as_hashes
    use_sources({ name: "h", url: "https://lists.example/h.txt", trust: :primary })
    stub_request(:get, "https://lists.example/h.txt").to_return(status: 200, body: "h.com\n")
    assert Updater.update
    assert_equal %w[h.com], stored
  end

  # =========================================================================
  # Writing
  # =========================================================================

  def test_large_lists_are_written_in_batches
    a = src("a")
    use_sources(a)
    stub_source(a, list(many(Updater::INSERT_BATCH_SIZE + 1_234)))
    assert Updater.update
    assert_equal Updater::INSERT_BATCH_SIZE + 1_234, Nondisposable::DisposableDomain.count

    stub_source(a, list(many(Updater::INSERT_BATCH_SIZE + 1_234, prefix: "e")))
    assert Updater.update
    assert_equal 0, Nondisposable::DisposableDomain.where("name LIKE 'd%'").count
  end

  # =========================================================================
  # Locking
  # =========================================================================

  # Pretends the test database (SQLite) has advisory locks, counting calls.
  LockCalls = Struct.new(:acquired, :released)

  def with_fake_lock(grant:)
    calls = LockCalls.new(0, 0)
    connection = ActiveRecord::Base.connection
    connection.stub(:supports_advisory_locks?, true) do
      connection.stub(:get_advisory_lock, ->(_id) { calls.acquired += 1; grant }) do
        connection.stub(:release_advisory_lock, ->(_id) { calls.released += 1; true }) do
          yield calls
        end
      end
    end
  end

  def test_publish_takes_and_releases_the_advisory_lock
    a = src("a")
    use_sources(a)
    stub_source(a, list("x.com"))
    assert Updater.update

    with_fake_lock(grant: true) do |fake|
      assert Updater.publish
      assert_equal 1, fake.acquired
      assert_equal 1, fake.released
    end
  end

  def test_publish_gives_up_when_another_process_holds_the_lock
    clock = [0.0, 0.0, Updater::PUBLISH_LOCK_WAIT + 1.0].each
    with_fake_lock(grant: false) do |fake|
      Updater.stub(:monotonic, -> { clock.next }) do
        Updater.stub(:sleep, nil) do
          log = capture_log { refute Updater.publish }
          assert_includes log, "Another process has been publishing"
        end
      end
      assert_equal 0, fake.released
    end
  end

  # =========================================================================
  # Rolling deploys
  # =========================================================================

  def test_without_the_table_custom_sources_fall_back_to_the_default_list
    drop_snapshots_table!
    use_sources(src("a"))
    stub = stub_source(DED, list("legacy.com"))

    log = capture_log { assert Updater.update }

    assert_requested stub
    assert_includes log, "rails g nondisposable:upgrade"
    assert_equal %w[legacy.com], stored
  end

  def test_without_the_table_an_invalid_sources_config_still_falls_back
    drop_snapshots_table!
    Nondisposable.configuration.sources = [{ name: "x", url: "http://insecure" }]
    stub_source(DED, list("legacy.com"))

    log = capture_log { assert Updater.update }
    assert_includes log, "customised"
  end

  def test_single_source_path_refuses_mostly_junk
    drop_snapshots_table!
    setup_disposable_domain!("existing.com")
    stub_source(DED, "<html>\n<p>oops</p>\nok.com\n")

    refute Updater.update
    assert_equal %w[existing.com], stored
  end
end
