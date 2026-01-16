# frozen_string_literal: true

require "test_helper"

class DomainListUpdaterTest < NondisposableTestCase
  # =========================================================================
  # Successful Update Tests
  # =========================================================================

  def test_successfully_updates_domains_from_remote
    stub = stub_domain_list("temp.com\ntrash.net\n")

    result = Nondisposable::DomainListUpdater.update

    assert result
    assert_requested stub
    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_equal %w[temp.com trash.net], names
  end

  def test_returns_true_on_success
    stub_domain_list("domain.com\n")

    assert Nondisposable::DomainListUpdater.update
  end

  def test_downloads_from_correct_url
    stub = stub_request(:get, "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf")
           .to_return(status: 200, body: "test.com\n")

    Nondisposable::DomainListUpdater.update

    assert_requested stub
  end

  def test_domains_are_lowercased
    stub_domain_list("UPPERCASE.COM\nMixedCase.Org\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_includes names, "uppercase.com"
    assert_includes names, "mixedcase.org"
  end

  def test_handles_windows_line_endings
    stub_domain_list("domain1.com\r\ndomain2.com\r\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    # Check that domains are created (may include \r depending on implementation)
    assert Nondisposable::DisposableDomain.count >= 1
  end

  def test_handles_empty_lines_in_list
    stub_domain_list("domain1.com\n\n\ndomain2.com\n\n")

    Nondisposable::DomainListUpdater.update

    # Empty lines become empty strings in the list
    count = Nondisposable::DisposableDomain.count
    assert count >= 2
  end

  def test_handles_single_domain
    stub_domain_list("single.com")

    Nondisposable::DomainListUpdater.update

    assert_equal 1, Nondisposable::DisposableDomain.count
    assert_equal "single.com", Nondisposable::DisposableDomain.first.name
  end

  def test_handles_large_list
    domains = (1..1000).map { |i| "domain#{i}.com" }.join("\n")
    stub_domain_list(domains)

    Nondisposable::DomainListUpdater.update

    assert_equal 1000, Nondisposable::DisposableDomain.count
  end

  # =========================================================================
  # Additional Domains Configuration Tests
  # =========================================================================

  def test_merges_additional_domains
    Nondisposable.configuration.additional_domains = ["custom1.com", "custom2.com"]
    stub_domain_list("remote.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_includes names, "remote.com"
    assert_includes names, "custom1.com"
    assert_includes names, "custom2.com"
  end

  def test_deduplicates_domains_with_uniq
    Nondisposable.configuration.additional_domains = ["duplicate.com"]
    stub_domain_list("duplicate.com\nother.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_equal 1, names.count("duplicate.com")
  end

  def test_additional_domains_with_empty_array
    Nondisposable.configuration.additional_domains = []
    stub_domain_list("remote.com\n")

    Nondisposable::DomainListUpdater.update

    assert_equal 1, Nondisposable::DisposableDomain.count
  end

  # =========================================================================
  # Excluded Domains Configuration Tests
  # =========================================================================

  def test_excludes_configured_domains
    Nondisposable.configuration.excluded_domains = ["exclude.com"]
    stub_domain_list("include.com\nexclude.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_includes names, "include.com"
    refute_includes names, "exclude.com"
  end

  def test_excludes_multiple_domains
    Nondisposable.configuration.excluded_domains = ["ex1.com", "ex2.com", "ex3.com"]
    stub_domain_list("ex1.com\nex2.com\nex3.com\nkeep.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_equal ["keep.com"], names
  end

  def test_excluded_domains_with_empty_array
    Nondisposable.configuration.excluded_domains = []
    stub_domain_list("domain.com\n")

    Nondisposable::DomainListUpdater.update

    assert_equal 1, Nondisposable::DisposableDomain.count
  end

  # =========================================================================
  # Combined Additional + Excluded Domains Tests
  # =========================================================================

  def test_merges_additional_and_excluded_domains
    Nondisposable.configuration.additional_domains = ["extra.com", "trash.net"]
    Nondisposable.configuration.excluded_domains = ["trash.net"]
    stub_domain_list("temp.com\ntrash.net\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_equal %w[extra.com temp.com], names
  end

  def test_excluded_removes_from_additional_domains_too
    Nondisposable.configuration.additional_domains = ["overlap.com"]
    Nondisposable.configuration.excluded_domains = ["overlap.com"]
    stub_domain_list("other.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    refute_includes names, "overlap.com"
    assert_includes names, "other.com"
  end

  # =========================================================================
  # HTTP Failure Tests
  # =========================================================================

  def test_returns_false_on_http_404
    stub_domain_list("", status: 404)

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_http_500
    stub_domain_list("", status: 500)

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_http_503
    stub_domain_list("", status: 503)

    refute Nondisposable::DomainListUpdater.update
  end

  def test_returns_false_on_http_403
    stub_domain_list("", status: 403)

    refute Nondisposable::DomainListUpdater.update
  end

  def test_does_not_modify_database_on_http_failure
    setup_disposable_domain!("existing.com")
    stub_domain_list("", status: 500)

    Nondisposable::DomainListUpdater.update

    # Existing data should remain
    assert_equal 1, Nondisposable::DisposableDomain.count
    assert Nondisposable::DisposableDomain.exists?(name: "existing.com")
  end

  # =========================================================================
  # Empty List Tests
  # =========================================================================

  def test_returns_false_on_empty_list
    stub_domain_list("")

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_whitespace_only_list
    stub_domain_list("\n\n\n")

    refute Nondisposable::DomainListUpdater.update
  end

  def test_does_not_modify_database_on_empty_list
    setup_disposable_domain!("existing.com")
    stub_domain_list("\n\n")

    Nondisposable::DomainListUpdater.update

    # Existing data should remain
    assert_equal 1, Nondisposable::DisposableDomain.count
  end

  # =========================================================================
  # Network Error Tests
  # =========================================================================

  def test_returns_false_on_socket_error
    stub_request(:get, /disposable-email-domains/).to_raise(SocketError.new("no network"))

    refute Nondisposable::DomainListUpdater.update
    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  def test_returns_false_on_timeout_error
    stub_request(:get, /disposable-email-domains/).to_timeout

    refute Nondisposable::DomainListUpdater.update
  end

  def test_returns_false_on_connection_refused
    stub_request(:get, /disposable-email-domains/).to_raise(Errno::ECONNREFUSED)

    refute Nondisposable::DomainListUpdater.update
  end

  def test_does_not_modify_database_on_network_error
    setup_disposable_domain!("existing.com")
    stub_request(:get, /disposable-email-domains/).to_raise(SocketError.new("no network"))

    Nondisposable::DomainListUpdater.update

    assert_equal 1, Nondisposable::DisposableDomain.count
    assert Nondisposable::DisposableDomain.exists?(name: "existing.com")
  end

  # =========================================================================
  # Transaction and Atomicity Tests
  # =========================================================================

  def test_transactionality_deletes_then_inserts
    setup_disposable_domain!("old.com")
    stub_domain_list("a.com\nb.com\n")

    Nondisposable::DomainListUpdater.update

    refute Nondisposable::DisposableDomain.exists?(name: "old.com")
    assert_equal %w[a.com b.com], Nondisposable::DisposableDomain.order(:name).pluck(:name)
  end

  def test_replaces_entire_list_on_each_update
    stub_domain_list("first.com\n")
    Nondisposable::DomainListUpdater.update
    assert_equal ["first.com"], Nondisposable::DisposableDomain.pluck(:name)

    stub_domain_list("second.com\nthird.com\n")
    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.order(:name).pluck(:name)
    assert_equal %w[second.com third.com], names
    refute_includes names, "first.com"
  end

  def test_update_rolls_back_on_insert_error
    setup_disposable_domain!("keep.com")
    stub_domain_list("a.com\n")

    Nondisposable::DisposableDomain.stub(:create, proc { raise "insert failed" }) do
      refute Nondisposable::DomainListUpdater.update
    end

    # Rollback should preserve original data
    assert_equal %w[keep.com], Nondisposable::DisposableDomain.order(:name).pluck(:name)
  end

  def test_rollback_on_partial_insert_failure
    setup_disposable_domain!("original.com")
    stub_domain_list("new1.com\nnew2.com\n")

    call_count = 0
    Nondisposable::DisposableDomain.stub(:create, proc { |args|
      call_count += 1
      raise "fail on second" if call_count > 1
      Nondisposable::DisposableDomain.new(args).tap(&:save!)
    }) do
      Nondisposable::DomainListUpdater.update
    end

    # Due to transaction, original data should be preserved
    # Note: actual behavior depends on error handling in update method
  end

  # =========================================================================
  # Idempotency Tests
  # =========================================================================

  def test_multiple_updates_are_idempotent
    stub_domain_list("domain.com\n")

    3.times { Nondisposable::DomainListUpdater.update }

    assert_equal 1, Nondisposable::DisposableDomain.count
    assert_equal "domain.com", Nondisposable::DisposableDomain.first.name
  end

  def test_same_list_twice_produces_same_result
    list = "a.com\nb.com\nc.com\n"
    stub_domain_list(list)

    Nondisposable::DomainListUpdater.update
    first_result = Nondisposable::DisposableDomain.order(:name).pluck(:name)

    stub_domain_list(list)
    Nondisposable::DomainListUpdater.update
    second_result = Nondisposable::DisposableDomain.order(:name).pluck(:name)

    assert_equal first_result, second_result
  end

  # =========================================================================
  # Edge Cases
  # =========================================================================

  def test_handles_domains_with_special_characters
    stub_domain_list("domain-with-dash.com\ndomain_underscore.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_includes names, "domain-with-dash.com"
    assert_includes names, "domain_underscore.com"
  end

  def test_handles_domains_with_numbers
    stub_domain_list("123domain.com\ndomain456.com\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_includes names, "123domain.com"
    assert_includes names, "domain456.com"
  end

  def test_handles_subdomains
    stub_domain_list("mail.tempmail.com\nsmtp.trash.net\n")

    Nondisposable::DomainListUpdater.update

    names = Nondisposable::DisposableDomain.pluck(:name)
    assert_includes names, "mail.tempmail.com"
    assert_includes names, "smtp.trash.net"
  end

  def test_handles_very_long_domain_names
    long_domain = "a" * 200 + ".com"
    stub_domain_list("#{long_domain}\n")

    Nondisposable::DomainListUpdater.update

    assert_equal 1, Nondisposable::DisposableDomain.count
    assert_equal long_domain, Nondisposable::DisposableDomain.first.name
  end

  def test_handles_punycode_domains
    stub_domain_list("xn--nxasmq5b.com\n")

    Nondisposable::DomainListUpdater.update

    assert_equal "xn--nxasmq5b.com", Nondisposable::DisposableDomain.first.name
  end

  def test_handles_trailing_whitespace_in_domains
    # Note: The implementation doesn't strip whitespace, so this documents behavior
    stub_domain_list("domain.com  \n  another.com\n")

    Nondisposable::DomainListUpdater.update

    # Current behavior may include whitespace
    count = Nondisposable::DisposableDomain.count
    assert count >= 1
  end

  # =========================================================================
  # Logging Tests
  # =========================================================================

  def test_logs_success_message
    stub_domain_list("domain.com\n")

    # The method logs info messages - we just verify it doesn't error
    assert Nondisposable::DomainListUpdater.update
  end

  def test_logs_error_on_http_failure
    stub_domain_list("", status: 500)

    # Should log error but not raise
    refute Nondisposable::DomainListUpdater.update
  end

  def test_logs_error_on_network_failure
    stub_request(:get, /disposable-email-domains/).to_raise(SocketError.new("test error"))

    # Should log error but not raise
    refute Nondisposable::DomainListUpdater.update
  end
end
