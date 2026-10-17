# frozen_string_literal: true

module Nondisposable
  class DisposableDomain < ApplicationRecord
    validates :name, presence: true, uniqueness: { case_sensitive: false }

    # How many leading labels the parent-domain walk strips when
    # check_parent_domains is enabled: user@a.b.c.tempmail.com is checked as
    # a.b.c.tempmail.com, b.c.tempmail.com, c.tempmail.com and tempmail.com.
    #
    # The walk never queries a public suffix — not a bare TLD like "com", and
    # since 0.6.0 not a multi-label one like "co.uk" or "github.io" either
    # (Nondisposable::PublicSuffix), so no single stored row can ever block a
    # whole namespace of unrelated registrants. Conversely, a throwaway address
    # nested more than 3 labels below a listed domain escapes the walk;
    # blocklisted domains are registrable domains, so 3 levels covers practical
    # abuse.
    PARENT_MATCH_DEPTH = 3

    class << self
      # Whether `domain` is disposable, according to the precedence table in
      # Nondisposable::Precedence: host exclusions, then the bundled
      # never-disposable list, then host additions, then the privacy-relay
      # policy, and only then this table.
      def disposable?(domain)
        domain = Nondisposable::Domain.normalize(domain)
        return false if domain.empty?

        verdict, candidates = Nondisposable::Precedence.decide(domain, match_candidates(domain))
        return verdict == :block unless verdict == :lookup

        candidates.any? && where(name: candidates).exists?
      end

      # The exact domain plus up to PARENT_MATCH_DEPTH parent domains, never a
      # public suffix (so never a bare TLD either). Expects a normalized domain.
      def match_candidates(domain)
        candidates = [domain]

        if Nondisposable.configuration.check_parent_domains
          labels = domain.split('.')
          1.upto(PARENT_MATCH_DEPTH) do |depth|
            parent = labels.drop(depth)
            break if parent.size < 2

            candidates << parent.join('.')
          end
        end

        # Never above the registrable domain: past it lie public suffixes and
        # names like `sch.uk` that sit above a wildcard suffix (`*.sch.uk`).
        registrable = Nondisposable::PublicSuffix.registrable_domain(domain)
        return [] unless registrable

        candidates.select { |candidate| candidate == registrable || candidate.end_with?(".#{registrable}") }
      end
    end

  end
end
