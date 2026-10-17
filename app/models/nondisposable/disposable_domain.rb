# frozen_string_literal: true

module Nondisposable
  class DisposableDomain < ApplicationRecord
    validates :name, presence: true, uniqueness: { case_sensitive: false }

    # Kept so code that referenced it still loads; no longer used. Until 0.6.0
    # the parent walk stopped after this many labels, which let anybody who
    # controls a listed domain escape it with `a.b.c.d.tempmail.com`. The walk
    # now covers every parent down to the registrable domain: DNS itself caps
    # a name at 253 characters, so the candidate list is bounded anyway.
    PARENT_MATCH_DEPTH = 3

    # Longest raw input worth normalizing: a 253-character DNS name, plus room
    # for whitespace and a unicode form that is longer before punycode.
    MAX_INPUT_LENGTH = 1_024
    # DNS caps a name at 253 characters, which also bounds the parent walk
    # (at most 127 labels).
    MAX_DOMAIN_LENGTH = 253

    class << self
      # Whether `domain` is disposable, according to the precedence table in
      # Nondisposable::Precedence: host exclusions, then the bundled
      # never-disposable list, then host additions, then the privacy-relay
      # policy, and only then this table.
      def disposable?(domain)
        # No list can hold a name DNS could never resolve, so refuse to do any
        # work for one: cheap length checks first, before normalizing or
        # walking parents, because the input is whatever a signup form sent.
        return false if domain.to_s.length > MAX_INPUT_LENGTH

        domain = Nondisposable::Domain.normalize(domain)
        return false if domain.empty? || domain.length > MAX_DOMAIN_LENGTH

        verdict, candidates = Nondisposable::Precedence.decide(domain, match_candidates(domain))
        return verdict == :block unless verdict == :lookup

        candidates.any? && where(name: candidates).exists? # one WHERE name IN (...)
      end

      # With check_parent_domains (the default): the domain and EVERY parent
      # down to, and including, its registrable domain:
      #
      #   a.b.c.d.tempmail.com => a.b.c.d.tempmail.com … d.tempmail.com, tempmail.com
      #
      # Never above the registrable domain: past it lie public suffixes (`com`,
      # `co.uk`) and names like `sch.uk` that sit above a wildcard suffix
      # (`*.sch.uk`), all belonging to unrelated registrants. Without
      # check_parent_domains: the domain alone. Expects a normalized domain.
      def match_candidates(domain)
        namespace = Nondisposable::Precedence.namespace(domain)
        return namespace if Nondisposable.configuration.check_parent_domains

        namespace.first(1)
      end
    end

  end
end
