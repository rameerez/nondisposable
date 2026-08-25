# frozen_string_literal: true

require "tmpdir"
require "test_helper"

# The maintenance task that refreshes the vendored IANA snapshot.
#
# Every test here writes to a temp file. The updater's default target is the
# real data/iana_tlds.txt shipped in the gem, and a test that clobbered it with
# a fixture would quietly ship a two-entry root zone in the next release.
class NondisposableTldListUpdaterTest < NondisposableTestCase
  IANA_URL = "https://data.iana.org/TLD/tlds-alpha-by-domain.txt"

  # A body that clears MINIMUM_PLAUSIBLE_TLD_COUNT, so the plausibility guard
  # doesn't reject perfectly good test fixtures.
  def plausible_body(header: "# Version 2026082301, Last Updated Mon Aug 24 07:07:01 2026 UTC")
    ([header] + (1..1_200).map { |i| "TESTTLD#{i}" }).join("\n") + "\n"
  end

  def with_temp_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "iana_tlds.txt")
      File.write(path, "# Version 1\nCOM\n")
      yield path
    end
  end

  def stub_iana(body, status: 200)
    stub_request(:get, IANA_URL).to_return(status: status, body: body)
  end

  # =========================================================================
  # The happy path
  # =========================================================================

  def test_writes_the_fetched_list_and_reports_the_count
    stub = stub_iana(plausible_body)

    with_temp_list do |path|
      count = Nondisposable::TldListUpdater.update(path: path)

      assert_requested stub
      assert_equal 1_200, count
      assert_includes File.read(path), "TESTTLD1"
    end
  end

  def test_keeps_ianas_version_header_verbatim
    # The header is the snapshot's provenance — which root zone, from when.
    # Nondisposable::Tld.version reads it back out.
    stub_iana(plausible_body)

    with_temp_list do |path|
      Nondisposable::TldListUpdater.update(path: path)

      assert_match(/\A# Version 2026082301,/, File.read(path))
    end
  end

  # =========================================================================
  # Refusing to make things worse
  # =========================================================================

  def test_refuses_to_overwrite_a_good_list_with_a_suspiciously_short_one
    # A captive portal, an error page served with a 200, a truncated body: all
    # arrive looking like a root zone that lost the internet. Writing that would
    # reject nearly every address on earth on the next release.
    stub_iana("# Version 1\nCOM\nNET\n")

    with_temp_list do |path|
      before = File.read(path)

      assert_nil Nondisposable::TldListUpdater.update(path: path)
      assert_equal before, File.read(path)
    end
  end

  def test_keeps_the_snapshot_when_the_fetch_fails
    stub_iana("nope", status: 500)

    with_temp_list do |path|
      before = File.read(path)

      assert_nil Nondisposable::TldListUpdater.update(path: path)
      assert_equal before, File.read(path)
    end
  end

  def test_keeps_the_snapshot_when_the_network_raises
    stub_request(:get, IANA_URL).to_raise(SocketError.new("getaddrinfo failed"))

    with_temp_list do |path|
      before = File.read(path)

      assert_nil Nondisposable::TldListUpdater.update(path: path)
      assert_equal before, File.read(path)
    end
  end

  def test_leaves_no_temp_file_behind_when_it_bails
    stub_iana("# Version 1\nCOM\n")

    with_temp_list do |path|
      Nondisposable::TldListUpdater.update(path: path)

      refute File.exist?("#{path}.tmp"), "a half-written root zone must never survive the run"
    end
  end

  # =========================================================================
  # The in-memory list picks the new data up
  # =========================================================================

  def test_reloads_the_memoized_set_after_a_successful_write
    # Without the reload the process would keep answering from the list it read
    # at boot, and the update would look like it did nothing.
    stub_iana(plausible_body)
    original_size = Nondisposable::Tld.all.size

    with_temp_list do |path|
      Nondisposable::TldListUpdater.update(path: path)
    end

    # Reloaded from the real bundled file (the temp path was the write target,
    # not the read target), so the count is unchanged and the Set is live.
    assert_equal original_size, Nondisposable::Tld.all.size
    assert Nondisposable::Tld.valid?("com")
  end
end
