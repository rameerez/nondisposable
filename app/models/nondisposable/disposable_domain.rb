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

    # Kept (and equal to Domain::MAX_RAW_LENGTH) for code that referenced it.
    # The raw-length bound itself now lives in Domain.normalize, which applies
    # it AFTER stripping invisible characters: judging raw length here let
    # padding hide a listed domain.
    MAX_INPUT_LENGTH = Nondisposable::Domain::MAX_RAW_LENGTH

    class << self
      # Whether `domain` is disposable, according to the precedence table in
      # Nondisposable::Precedence: host exclusions, then the bundled
      # never-disposable list, then host additions, then the privacy-relay
      # policy, and only then this table.
      def disposable?(domain)
        # A name longer than DNS allows (over 253 characters or a label over
        # 63 once canonical, or over 1,024 code points of raw input after
        # invisible characters are stripped) is TRUE: it can never be a
        # deliverable domain, and a check whose job is keeping junk out must
        # not call junk fine. Judged by Domain.too_long?, never on the raw
        # length: a raw cap let invisible padding (U+00AD x 1013 +
        # "tempmail.com") hide a listed name. Domain.normalize bounds its own
        # work on oversized input, so the parent walk below never runs on one.
        raw = domain
        return false if raw.to_s.strip.empty?
        return true if Nondisposable::Domain.too_long?(raw)

        domain = Nondisposable::Domain.normalize(raw)
        return false if domain.empty?
        # Not UTF-8: no list holds it and no mail server can deliver to it.
        return false if domain.encoding == Encoding::BINARY && !domain.ascii_only?

        verdict, candidates = Nondisposable::Precedence.decide(domain, match_candidates(domain))
        return verdict == :block unless verdict == :lookup

        # Rows written before 0.5.0 stored a unicode domain as it came
        # (lowercased, not punycode). Match that spelling of every candidate
        # still eligible, so upgrading never unblocks them; the next publish
        # rewrites them canonically.
        legacy = Nondisposable::Domain.unicode(raw)
        unless legacy == domain || legacy.ascii_only?
          candidates |= match_candidates(legacy).select { |name| candidates.include?(Nondisposable::Domain.normalize(name)) }
        end

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
