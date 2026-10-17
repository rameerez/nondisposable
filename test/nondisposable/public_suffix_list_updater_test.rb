# frozen_string_literal: true

require "tmpdir"
require "test_helper"

# The maintenance task that refreshes the vendored Public Suffix List. Every
# test writes to a temp file, never to the data/ file that ships in the gem.
class NondisposablePublicSuffixListUpdaterTest < NondisposableTestCase
  PSL_URL = "https://publicsuffix.org/list/public_suffix_list.dat"

  def plausible_body
    rules = (1..6_000).map { |i| "suffix#{i}" }
    "// VERSION: 2026-10-17_00-00-00_UTC\n// ===BEGIN ICANN DOMAINS===\n#{rules.join("\n")}\n// ===END ICANN DOMAINS===\n"
  end

  def with_temp_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "public_suffix_list.dat")
      File.write(path, "// old\ncom\n")
      yield path
    end
  ensure
    Nondisposable::PublicSuffix.reload!
  end

  def test_writes_a_plausible_list
    stub_request(:get, PSL_URL).to_return(status: 200, body: plausible_body)

    with_temp_list do |path|
      assert_equal 6_000, Nondisposable::PublicSuffixListUpdater.update(path: path)
      assert_includes File.read(path), "suffix6000"
      refute File.exist?("#{path}.tmp")
    end
  end

  def test_refuses_a_short_or_sectionless_body
    stub_request(:get, PSL_URL).to_return(status: 200, body: "<html>maintenance</html>\n")

    with_temp_list do |path|
      before = File.read(path)
      assert_nil Nondisposable::PublicSuffixListUpdater.update(path: path)
      assert_equal before, File.read(path)
    end
  end

  def test_keeps_the_snapshot_on_http_failure
    stub_request(:get, PSL_URL).to_return(status: 500, body: "")

    with_temp_list do |path|
      assert_nil Nondisposable::PublicSuffixListUpdater.update(path: path)
    end
  end

  def test_keeps_the_snapshot_when_the_network_raises
    stub_request(:get, PSL_URL).to_raise(SocketError.new("getaddrinfo failed"))

    with_temp_list do |path|
      assert_nil Nondisposable::PublicSuffixListUpdater.update(path: path)
    end
  end

  def test_logs_to_stderr_without_rails_logger
    stub_request(:get, PSL_URL).to_return(status: 500, body: "")
    Rails.stub(:logger, nil) do
      with_temp_list do |path|
        _out, err = capture_io { Nondisposable::PublicSuffixListUpdater.update(path: path) }
        assert_includes err, "[nondisposable]"
      end
    end
  end
end
