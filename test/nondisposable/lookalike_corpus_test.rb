# frozen_string_literal: true

require "test_helper"
require "csv"
require "digest"

# The labelled corpus: every domain the pre-0.5.0 rule flagged in the Tranco
# top 1M, plus the typos seen on real accounts, each labelled typo / real /
# uncertain with the evidence behind it (see script/label_lookalike_corpus.rb).
#
# Two different questions are asked of it, and they must not be confused:
#
#   1. HARD REJECTION is judged on provenance. Every entry in
#      data/known_typo_domains.txt must be a `typo` row with evidence, and no
#      other row may ever be refused outright. The list is not tested for
#      "accuracy" against the corpus, because it was built from the corpus —
#      that test would be circular (codex finding 1).
#   2. THE RANKER (Suggestion.guess, the list left out) is judged on a holdout
#      it was never tuned on: a deterministic 30% of rows by hash of the
#      domain, fixed before any filter was written. Floors on both precision
#      and recall, because "suggest nothing" would otherwise score perfectly.
class NondisposableLookalikeCorpusTest < NondisposableTestCase
  CORPUS_PATH = File.expand_path("../fixtures/lookalike_corpus.csv", __dir__)
  LABELS = %w[typo real uncertain].freeze

  # Measured on the holdout when the filters landed (2026-10-17): precision
  # 0.484 (15 of 31 suggestions), recall 0.833 (15 of 18 typos). Distance
  # alone, on the same rows: precision 0.093. The floors sit just under the
  # measurement, so a regression fails loudly and a small corpus correction
  # does not.
  HOLDOUT_PRECISION_FLOOR = 0.45
  HOLDOUT_RECALL_FLOOR = 0.80

  def self.corpus
    @corpus ||= CSV.read(CORPUS_PATH, headers: true).map(&:to_h).freeze
  end

  # Decided by the domain alone, so it cannot drift as rows are added or
  # relabelled, and nobody can move a row into the tuning set by editing it.
  def self.holdout?(domain)
    Digest::SHA256.hexdigest(domain)[0, 8].to_i(16) % 10 < 3
  end

  def corpus = self.class.corpus

  def test_every_row_has_a_known_label_and_evidence
    corpus.each do |row|
      assert_includes LABELS, row["label"], "#{row['domain']}: unknown label"
      refute_empty row["evidence"].to_s.strip, "#{row['domain']}: a label without evidence is an opinion"
    end
  end

  def test_the_corpus_covers_the_tranco_scan_and_the_production_typos
    domains = corpus.map { |row| row["domain"] }.to_set
    tranco = CSV.read(File.expand_path("../../docs/evidence/2026-10-17-tranco-top1m-lookalike-hits.csv", __dir__)).map { |r| r[1] }

    assert_empty tranco.to_set - domains
    assert_empty %w[gmailmcom gmail.con outlook.ed gmai.com gmal.com jmail.com].to_set - domains
  end

  # =========================================================================
  # 1. Hard rejection: provenance only
  # =========================================================================

  def test_every_known_typo_has_a_typo_row_with_evidence
    by_domain = corpus.to_h { |row| [row["domain"], row] }

    Nondisposable::KnownTypos.all.each do |typo, correction|
      row = by_domain[typo]
      refute_nil row, "#{typo} is on the hard-reject list with no evidence row in the corpus"
      assert_equal "typo", row["label"], "#{typo} is on the hard-reject list but labelled #{row['label']}"
      assert_includes Nondisposable::Suggestion.providers, correction, "#{typo} corrects to #{correction}, which is not a provider"
    end
  end

  def test_no_real_or_uncertain_row_is_ever_refused_outright
    Nondisposable.configure { |c| c.reject_lookalike_domains = :confirmable }

    corpus.reject { |row| row["label"] == "typo" }.each do |row|
      refute Nondisposable::KnownTypos.include?(row["domain"]), "#{row['domain']} (#{row['label']}) is hard-rejected"

      user = ConfirmingUser.new(email: "someone@#{row['domain']}", email_lookalike_confirmed: "1")
      assert user.valid?, "#{row['domain']} (#{row['label']}: #{row['evidence']}) cannot get through even when confirmed"
    end
  end

  # =========================================================================
  # 2. The ranker, on the untouched holdout
  # =========================================================================

  def test_the_ranker_holds_its_precision_and_recall_on_the_holdout
    stats = self.class.ranker_stats(corpus.select { |row| self.class.holdout?(row["domain"]) })

    assert_operator stats[:precision], :>=, HOLDOUT_PRECISION_FLOOR, "holdout precision fell: #{stats.inspect}"
    assert_operator stats[:recall], :>=, HOLDOUT_RECALL_FLOOR, "holdout recall fell: #{stats.inspect}"
  end

  def test_the_holdout_is_a_real_sample
    holdout = corpus.select { |row| self.class.holdout?(row["domain"]) }

    assert_operator holdout.size, :>, corpus.size / 5
    assert_operator holdout.count { |row| row["label"] == "typo" }, :>=, 10
    assert_operator holdout.count { |row| row["label"] == "real" }, :>=, 50
  end

  # Precision over typo + real (uncertain rows say nothing either way);
  # recall over typo rows.
  def self.ranker_stats(rows)
    judged = rows.select { |row| %w[typo real].include?(row["label"]) }
    flagged = judged.select { |row| Nondisposable::Suggestion.guess(row["domain"]) }
    true_positives = flagged.count { |row| row["label"] == "typo" }
    typos = judged.count { |row| row["label"] == "typo" }

    {
      rows: rows.size, typo: typos, real: judged.size - typos, flagged: flagged.size,
      true_positives: true_positives,
      precision: flagged.empty? ? 1.0 : true_positives.fdiv(flagged.size),
      recall: typos.zero? ? 1.0 : true_positives.fdiv(typos),
      real_flagged: flagged.select { |row| row["label"] == "real" }.map { |row| row["domain"] }
    }
  end
end
