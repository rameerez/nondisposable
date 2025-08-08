# frozen_string_literal: true

require "test_helper"

class DisposableDomainModelTest < Minitest::Test
  def setup
    Nondisposable.configuration = Nondisposable::Configuration.new
    Nondisposable::DisposableDomain.delete_all
  end

  def test_validates_presence_and_uniqueness_case_insensitive
    d1 = Nondisposable::DisposableDomain.create!(name: "TempMail.com")
    d2 = Nondisposable::DisposableDomain.new(name: "tempmail.com")

    refute d2.valid?
    assert_includes d2.errors[:name], "has already been taken"

    d1.update!(name: "new.com")
    d2.name = "tempmail.com"
  end

  def test_disposable_query_with_blank
    refute Nondisposable::DisposableDomain.disposable?(nil)
    refute Nondisposable::DisposableDomain.disposable?("")
  end

  def test_disposable_query_true_when_in_db
    Nondisposable::DisposableDomain.create!(name: "foo.com")
    assert Nondisposable::DisposableDomain.disposable?("foo.com")
    assert Nondisposable::DisposableDomain.disposable?("FOO.COM"), "should be case-insensitive"
  end

  def test_disposable_query_true_when_in_additional_domains
    Nondisposable.configuration.additional_domains = ["bar.com"]
    assert Nondisposable::DisposableDomain.disposable?("bar.com")
  end

  def test_disposable_query_false_when_excluded
    Nondisposable::DisposableDomain.create!(name: "baz.com")
    Nondisposable.configuration.excluded_domains = ["baz.com"]
    refute Nondisposable::DisposableDomain.disposable?("baz.com")
  end
end