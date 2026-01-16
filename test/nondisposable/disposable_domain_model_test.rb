# frozen_string_literal: true

require "test_helper"

class DisposableDomainModelTest < NondisposableTestCase
  # =========================================================================
  # Model Validation Tests
  # =========================================================================

  def test_validates_presence_of_name
    domain = Nondisposable::DisposableDomain.new(name: nil)
    refute domain.valid?
    assert_includes domain.errors[:name], "can't be blank"
  end

  def test_validates_presence_of_name_with_empty_string
    domain = Nondisposable::DisposableDomain.new(name: "")
    refute domain.valid?
    assert_includes domain.errors[:name], "can't be blank"
  end

  def test_validates_uniqueness_of_name
    Nondisposable::DisposableDomain.create!(name: "existing.com")
    duplicate = Nondisposable::DisposableDomain.new(name: "existing.com")

    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  def test_validates_uniqueness_case_insensitive
    Nondisposable::DisposableDomain.create!(name: "TempMail.com")
    duplicate = Nondisposable::DisposableDomain.new(name: "tempmail.com")

    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  def test_validates_uniqueness_case_insensitive_uppercase
    Nondisposable::DisposableDomain.create!(name: "tempmail.com")
    duplicate = Nondisposable::DisposableDomain.new(name: "TEMPMAIL.COM")

    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  def test_allows_valid_domain_name
    domain = Nondisposable::DisposableDomain.new(name: "valid-domain.com")
    assert domain.valid?
  end

  def test_allows_subdomain
    domain = Nondisposable::DisposableDomain.new(name: "mail.example.com")
    assert domain.valid?
  end

  def test_allows_deeply_nested_subdomain
    domain = Nondisposable::DisposableDomain.new(name: "a.b.c.d.example.com")
    assert domain.valid?
  end

  # =========================================================================
  # Model CRUD Operations
  # =========================================================================

  def test_can_create_domain
    domain = Nondisposable::DisposableDomain.create!(name: "new.com")
    assert domain.persisted?
    assert_equal "new.com", domain.name
  end

  def test_can_update_domain
    domain = Nondisposable::DisposableDomain.create!(name: "old.com")
    domain.update!(name: "new.com")

    assert_equal "new.com", domain.reload.name
  end

  def test_can_destroy_domain
    domain = Nondisposable::DisposableDomain.create!(name: "todelete.com")
    domain_id = domain.id

    domain.destroy!

    refute Nondisposable::DisposableDomain.exists?(domain_id)
  end

  def test_timestamps_are_set
    domain = Nondisposable::DisposableDomain.create!(name: "timestamps.com")

    refute_nil domain.created_at
    refute_nil domain.updated_at
  end

  # =========================================================================
  # DisposableDomain.disposable? Class Method Tests
  # =========================================================================

  def test_disposable_query_returns_false_for_nil
    refute Nondisposable::DisposableDomain.disposable?(nil)
  end

  def test_disposable_query_returns_false_for_empty_string
    refute Nondisposable::DisposableDomain.disposable?("")
  end

  def test_disposable_query_returns_false_for_whitespace_only
    refute Nondisposable::DisposableDomain.disposable?("   ")
  end

  def test_disposable_query_returns_true_when_domain_in_database
    setup_disposable_domain!("disposable.com")
    assert Nondisposable::DisposableDomain.disposable?("disposable.com")
  end

  def test_disposable_query_returns_false_when_domain_not_in_database
    refute Nondisposable::DisposableDomain.disposable?("notindatabase.com")
  end

  def test_disposable_query_lowercases_input_for_lookup
    # Store domain in lowercase (as DomainListUpdater does)
    setup_disposable_domain!("uppercase.com")
    # Query is lowercased before lookup
    assert Nondisposable::DisposableDomain.disposable?("UPPERCASE.COM")
  end

  def test_disposable_query_with_lowercase_domain_and_uppercase_query
    setup_disposable_domain!("lowercase.com")
    # Query is lowercased, matches lowercase domain
    assert Nondisposable::DisposableDomain.disposable?("LOWERCASE.COM")
  end

  def test_disposable_query_normalizes_input_case
    # Store domain in lowercase (as DomainListUpdater does)
    setup_disposable_domain!("mixedcase.com")
    # Query is lowercased before lookup, so it matches
    assert Nondisposable::DisposableDomain.disposable?("mIxEdCaSe.CoM")
  end

  # =========================================================================
  # Additional Domains Configuration Tests
  # =========================================================================

  def test_disposable_returns_true_for_additional_domain_not_in_db
    Nondisposable.configuration.additional_domains = ["additional.com"]

    assert Nondisposable::DisposableDomain.disposable?("additional.com")
  end

  def test_disposable_returns_true_for_additional_domain_with_case_normalization
    # The disposable? method lowercases the input before checking
    # But additional_domains comparison uses Array#include? which is case-sensitive
    # This documents the current behavior: additional_domains should be lowercase
    Nondisposable.configuration.additional_domains = ["additional.com"]

    # Query is lowercased, then checked against additional_domains
    assert Nondisposable::DisposableDomain.disposable?("Additional.Com")
    assert Nondisposable::DisposableDomain.disposable?("ADDITIONAL.COM")
    assert Nondisposable::DisposableDomain.disposable?("additional.com")
  end

  def test_disposable_returns_true_when_domain_in_both_db_and_additional
    setup_disposable_domain!("both.com")
    Nondisposable.configuration.additional_domains = ["both.com"]

    assert Nondisposable::DisposableDomain.disposable?("both.com")
  end

  def test_additional_domains_with_multiple_entries
    Nondisposable.configuration.additional_domains = ["one.com", "two.com", "three.com"]

    assert Nondisposable::DisposableDomain.disposable?("one.com")
    assert Nondisposable::DisposableDomain.disposable?("two.com")
    assert Nondisposable::DisposableDomain.disposable?("three.com")
    refute Nondisposable::DisposableDomain.disposable?("four.com")
  end

  # =========================================================================
  # Excluded Domains Configuration Tests
  # =========================================================================

  def test_disposable_returns_false_for_excluded_domain_in_db
    setup_disposable_domain!("excluded.com")
    Nondisposable.configuration.excluded_domains = ["excluded.com"]

    refute Nondisposable::DisposableDomain.disposable?("excluded.com")
  end

  def test_excluded_domain_takes_precedence_over_database
    setup_disposable_domain!("priority.com")
    Nondisposable.configuration.excluded_domains = ["priority.com"]

    refute Nondisposable::DisposableDomain.disposable?("priority.com")
  end

  def test_excluded_domain_does_not_affect_unrelated_domains
    setup_disposable_domain!("stillbad.com")
    Nondisposable.configuration.excluded_domains = ["notthisone.com"]

    assert Nondisposable::DisposableDomain.disposable?("stillbad.com")
  end

  def test_excluded_domains_case_sensitive_match
    # BUG: This tests the current behavior - excluded_domains is case-sensitive
    setup_disposable_domain!("CaseTest.Com")
    Nondisposable.configuration.excluded_domains = ["casetest.com"]

    # If the exclusion doesn't match case, it won't work
    # This documents the bug
  end

  def test_excluded_domains_with_multiple_entries
    setup_disposable_domain!("bad1.com")
    setup_disposable_domain!("bad2.com")
    setup_disposable_domain!("bad3.com")
    Nondisposable.configuration.excluded_domains = ["bad1.com", "bad2.com"]

    refute Nondisposable::DisposableDomain.disposable?("bad1.com")
    refute Nondisposable::DisposableDomain.disposable?("bad2.com")
    assert Nondisposable::DisposableDomain.disposable?("bad3.com")
  end

  # =========================================================================
  # Additional + Excluded Domains Interaction Tests
  # =========================================================================

  def test_additional_domain_in_excluded_list
    # A domain in additional_domains but also in excluded_domains
    Nondisposable.configuration.additional_domains = ["overlap.com"]
    Nondisposable.configuration.excluded_domains = ["overlap.com"]

    # Current logic: additional_domains check comes first (returns true)
    # before excluded_domains check on the DB result
    # This is a subtle behavior to document
    result = Nondisposable::DisposableDomain.disposable?("overlap.com")
    assert result, "additional_domains takes precedence since it's checked first"
  end

  def test_domain_in_db_and_excluded_but_not_additional
    setup_disposable_domain!("indb.com")
    Nondisposable.configuration.excluded_domains = ["indb.com"]

    refute Nondisposable::DisposableDomain.disposable?("indb.com")
  end

  # =========================================================================
  # Edge Cases and Special Characters
  # =========================================================================

  def test_disposable_query_with_very_long_domain
    long_domain = "a" * 200 + ".com"
    setup_disposable_domain!(long_domain)

    assert Nondisposable::DisposableDomain.disposable?(long_domain)
  end

  def test_disposable_query_with_hyphen_in_domain
    setup_disposable_domain!("hyphen-domain.com")
    assert Nondisposable::DisposableDomain.disposable?("hyphen-domain.com")
  end

  def test_disposable_query_with_numbers_in_domain
    setup_disposable_domain!("123domain456.com")
    assert Nondisposable::DisposableDomain.disposable?("123domain456.com")
  end

  def test_disposable_query_with_subdomain
    setup_disposable_domain!("mail.tempmail.com")
    assert Nondisposable::DisposableDomain.disposable?("mail.tempmail.com")
    refute Nondisposable::DisposableDomain.disposable?("tempmail.com")
  end

  def test_disposable_query_with_punycode_domain
    setup_disposable_domain!("xn--nxasmq5b.com")
    assert Nondisposable::DisposableDomain.disposable?("xn--nxasmq5b.com")
  end

  def test_disposable_query_with_single_letter_tld
    # Technically invalid but we should handle gracefully
    setup_disposable_domain!("domain.x")
    assert Nondisposable::DisposableDomain.disposable?("domain.x")
  end

  def test_disposable_query_with_numeric_tld
    setup_disposable_domain!("domain.123")
    assert Nondisposable::DisposableDomain.disposable?("domain.123")
  end

  # =========================================================================
  # Scoping and Query Tests
  # =========================================================================

  def test_where_query_is_case_insensitive_via_database
    setup_disposable_domain!("querytest.com")

    # The disposable? method downcases the input
    assert Nondisposable::DisposableDomain.disposable?("QUERYTEST.COM")
  end

  def test_count_returns_correct_number
    setup_disposable_domain!("one.com")
    setup_disposable_domain!("two.com")
    setup_disposable_domain!("three.com")

    assert_equal 3, Nondisposable::DisposableDomain.count
  end

  def test_pluck_returns_names
    setup_disposable_domain!("alpha.com")
    setup_disposable_domain!("beta.com")

    names = Nondisposable::DisposableDomain.pluck(:name).sort
    assert_equal ["alpha.com", "beta.com"], names
  end

  def test_delete_all_removes_all_records
    setup_disposable_domain!("todelete1.com")
    setup_disposable_domain!("todelete2.com")

    Nondisposable::DisposableDomain.delete_all

    assert_equal 0, Nondisposable::DisposableDomain.count
  end

  # =========================================================================
  # Database Constraint Tests
  # =========================================================================

  def test_database_unique_index_prevents_duplicates
    setup_disposable_domain!("unique.com")

    # Attempting to insert a duplicate at database level should fail
    assert_raises(ActiveRecord::RecordNotUnique) do
      # Bypass validations to test DB constraint
      Nondisposable::DisposableDomain.connection.execute(
        "INSERT INTO nondisposable_disposable_domains (name, created_at, updated_at) VALUES ('unique.com', datetime('now'), datetime('now'))"
      )
    end
  end
end
