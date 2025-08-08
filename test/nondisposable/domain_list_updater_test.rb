# frozen_string_literal: true

require "test_helper"

class DomainListUpdaterTest < Minitest::Test
  def setup
    Nondisposable.configuration = Nondisposable::Configuration.new
    Nondisposable::DisposableDomain.delete_all
  end

  def test_successfully_updates_domains_from_remote
    body = "temp.com\ntrash.net\n"
    stub = stub_request(:get, %r{raw\.githubusercontent\.com/.*/disposable_email_blocklist\.conf}).to_return(status: 200, body: body)

    assert Nondisposable::DomainListUpdater.update
    assert_requested stub
    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_equal %w[temp.com trash.net], names
  end

  def test_merges_additional_and_excluded_domains
    Nondisposable.configuration.additional_domains = ["extra.com", "trash.net"]
    Nondisposable.configuration.excluded_domains = ["trash.net"]

    body = "temp.com\ntrash.net\n"
    stub_request(:get, /disposable-email-domains/).to_return(status: 200, body: body)

    assert Nondisposable::DomainListUpdater.update
    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_equal %w[extra.com temp.com], names
  end

  def test_returns_false_on_http_failure
    stub_request(:get, /disposable-email-domains/).to_return(status: 500, body: "")

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_empty_list
    stub_request(:get, /disposable-email-domains/).to_return(status: 200, body: "\n\n")

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_network_error
    stub_request(:get, /disposable-email-domains/).to_raise(SocketError.new("no network"))

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_transactionality_deletes_then_inserts
    body = "a.com\nb.com\n"
    stub_request(:get, /disposable-email-domains/).to_return(status: 200, body: body)

    Nondisposable::DisposableDomain.create!(name: "old.com")
    assert Nondisposable::DomainListUpdater.update
    refute Nondisposable::DisposableDomain.exists?(name: "old.com")
    assert_equal %w[a.com b.com], Nondisposable::DisposableDomain.order(:name).pluck(:name)
  end

  def test_update_rolls_back_on_insert_error
    # Pre-populate with a domain that should remain if the transaction rolls back
    Nondisposable::DisposableDomain.create!(name: "keep.com")

    body = "a.com\n"
    stub_request(:get, /disposable-email-domains/).to_return(status: 200, body: body)

    Nondisposable::DisposableDomain.stub(:create, proc { raise "insert failed" }) do
      refute Nondisposable::DomainListUpdater.update
    end

    # Ensure rollback kept the original data
    assert_equal %w[keep.com], Nondisposable::DisposableDomain.order(:name).pluck(:name)
  end
end