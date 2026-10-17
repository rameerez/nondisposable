# frozen_string_literal: true

require "test_helper"

# The labeller is what decides which rows may ever be hard-rejected, so its
# "undeliverable" guard gets a test of its own. Loaded into an anonymous
# module so its constants never leak into the suite.
class NondisposableLookalikeLabellerTest < NondisposableTestCase
  PATH = File.expand_path("../../script/label_lookalike_corpus.rb", __dir__)

  def labeller
    @labeller ||= begin
      mod = Module.new
      mod.module_eval(File.read(PATH), PATH)
      Object.new.extend(mod)
    end
  end

  def row(**fields)
    { "domain" => "gmal.com", "dns_status" => "MX:NOERROR A:NOERROR AAAA:NOERROR", "resolves" => "no", "mx" => "" }
      .merge(fields.transform_keys(&:to_s))
  end

  def test_nothing_to_deliver_to_is_undeliverable
    assert labeller.undeliverable_evidence?(row)
  end

  def test_a_remote_mx_means_mail_can_be_delivered_even_without_an_address
    # Remote SMTP needs no apex address: an MX alone defeats the verdict.
    refute labeller.undeliverable_evidence?(row(mx: "mx.example.net"))
    refute labeller.self_mx_undeliverable?(row(mx: "mx.example.net"))
  end

  def test_a_lookup_that_did_not_answer_proves_nothing
    refute labeller.undeliverable_evidence?(row(dns_status: "MX:TIMEOUT A:NOERROR AAAA:NOERROR"))
    refute labeller.undeliverable_evidence?(row(dns_status: "MX:NOERROR A:SERVFAIL AAAA:NOERROR"))
  end

  def test_an_address_record_means_mail_can_be_delivered
    refute labeller.undeliverable_evidence?(row(resolves: "yes"))
  end

  def test_an_mx_pointing_at_the_domain_itself_counts_only_when_it_has_no_address
    assert labeller.self_mx_undeliverable?(row(domain: "hotmai.com", mx: "hotmai.com"))
    refute labeller.self_mx_undeliverable?(row(domain: "hotmai.com", mx: "hotmai.com", resolves: "yes"))
  end

  def test_the_guard_refuses_a_reviewed_undeliverable_label_the_evidence_no_longer_backs
    error = assert_raises(SystemExit) do
      capture_io { labeller.check_undeliverable!([row(mx: "mx.example.net")]) }
    end
    refute error.success?
  end
end
