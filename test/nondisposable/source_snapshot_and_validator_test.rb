# frozen_string_literal: true

require "test_helper"

class NondisposableSourceSnapshotTest < NondisposableTestCase
  Snapshot = Nondisposable::SourceSnapshot

  def setup
    super
    create_snapshots_table!
  end

  def teardown
    drop_snapshots_table!
    super
  end

  def snap(status, at, domains: nil)
    Snapshot.create!(source: "s", status: status, fetched_at: at, domains: domains)
  end

  def test_validates_status_and_presence
    refute Snapshot.new(source: "s", status: "maybe", fetched_at: Time.current).valid?
    refute Snapshot.new(status: "ok", fetched_at: Time.current).valid?
  end

  def test_last_good_ignores_other_statuses
    old = snap("ok", 3.days.ago, domains: "a.com\nb.com")
    snap("failed", 1.day.ago)
    snap("rolled_back", 2.hours.ago)

    assert_equal old, Snapshot.last_good("s")
    assert_equal %w[a.com b.com], old.domain_list
    assert_nil Snapshot.last_good("other")
  end

  def test_prune_keeps_recent_rows_and_the_last_good_one
    good = snap("ok", 30.days.ago)
    10.times { |i| snap("failed", i.hours.ago) }

    Snapshot.prune("s")

    assert_equal Snapshot::RETAINED_PER_SOURCE + 1, Snapshot.where(source: "s").count
    assert Snapshot.exists?(good.id)
  end

  def test_available_is_false_when_the_check_raises
    Snapshot.stub(:connection_pool, proc { raise ActiveRecord::ConnectionNotEstablished }) do
      refute Snapshot.available?
    end
  end
end

# The validator goes through the same precedence table as the list.
class NondisposableValidatorPrecedenceTest < NondisposableTestCase
  def test_privacy_relays_pass_by_default_and_fail_on_request
    setup_disposable_domain!("duck.com")
    assert User.new(email: "me@duck.com").valid?

    Nondisposable.configuration.block_privacy_relays = true
    user = User.new(email: "me@duck.com")
    refute user.valid?
    assert_includes user.errors[:email], "provider is not allowed"
  end

  def test_real_providers_pass_even_if_a_stale_table_lists_them
    setup_disposable_domain!("sify.com")
    assert User.new(email: "someone@sify.com").valid?
  end

  def test_host_exclusion_beats_host_addition
    Nondisposable.configuration.additional_domains = ["corp.example.com"]
    Nondisposable.configuration.excluded_domains = ["corp.example.com"]
    assert User.new(email: "a@corp.example.com").valid?
  end

  def test_trailing_dot_and_uppercase_are_the_same_domain
    setup_disposable_domain!("tempmail.com")
    refute User.new(email: "a@TempMail.com.").valid?
  end
end
