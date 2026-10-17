# frozen_string_literal: true

require "test_helper"

class NondisposableSourceFetcherTest < NondisposableTestCase
  URL = "https://example.com/list.txt"

  def source(**overrides)
    Nondisposable::Source.new(**{ name: "example", url: URL }.merge(overrides))
  end

  def fetch(src = source)
    Nondisposable::SourceFetcher.fetch(src)
  end

  def test_returns_the_body_as_utf8
    stub_request(:get, URL).to_return(status: 200, body: "a.com\nbücher.de\n")
    body = fetch
    assert_equal "a.com\nbücher.de\n", body
    assert_equal Encoding::UTF_8, body.encoding
  end

  def test_scrubs_invalid_bytes
    stub_request(:get, URL).to_return(status: 200, body: "a.com\n\xFF\n".b)
    assert_equal "a.com\n\n", fetch
  end

  def test_non_success_status_raises
    stub_request(:get, URL).to_return(status: 503, body: "down")
    error = assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch }
    assert_includes error.message, "503"
  end

  def test_redirects_are_not_followed
    stub = stub_request(:get, URL).to_return(status: 301, headers: { "Location" => "https://elsewhere.example/" })
    other = stub_request(:get, "https://elsewhere.example/")
    assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch }
    assert_requested stub
    assert_not_requested other
  end

  def test_declared_size_over_the_cap_is_refused_before_reading
    stub_request(:get, URL).to_return(status: 200, body: "a.com\n", headers: { "Content-Length" => "999999999" })
    error = assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch(source(max_bytes: 1_000)) }
    assert_includes error.message, "declared size"
  end

  def test_streamed_body_over_the_cap_is_abandoned
    stub_request(:get, URL).to_return(status: 200, body: "a.com\n" * 1_000)
    error = assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch(source(max_bytes: 100)) }
    assert_includes error.message, "max_bytes"
  end

  def test_download_past_the_deadline_is_abandoned
    stub_request(:get, URL).to_return(status: 200, body: "a.com\n")
    clock = [0.0, 31.0].each
    Nondisposable::SourceFetcher.stub(:monotonic, -> { clock.next }) do
      error = assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch }
      assert_includes error.message, "deadline"
    end
  end

  def test_a_stalled_exchange_is_cut_off_at_the_deadline
    # Headers trickling in within each read timeout never reach the per-chunk
    # check; the absolute timeout catches them.
    stall = proc { |*_args, **_opts| sleep 2 }
    Net::HTTP.stub(:start, stall) do
      error = assert_raises(Nondisposable::SourceFetcher::FetchError) { fetch(source(deadline: 0.2)) }
      assert_includes error.message, "deadline"
    end
  end

  def test_timeouts_never_exceed_the_deadline
    captured = nil
    fake_start = proc { |_host, _port, **options|
      captured = options
      raise Net::OpenTimeout, "execution expired"
    }

    Net::HTTP.stub(:start, fake_start) do
      assert_raises(Net::OpenTimeout) { fetch(source(deadline: 3)) }
    end
    assert_equal 3, captured[:open_timeout]
    assert_equal 3, captured[:read_timeout]
    assert captured[:use_ssl]
  end
end
