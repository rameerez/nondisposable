# frozen_string_literal: true

module Nondisposable
  class DisposableDomain < ApplicationRecord
    validates :name, presence: true, uniqueness: { case_sensitive: false }

    # How many leading labels the parent-domain walk strips when
    # check_parent_domains is enabled: user@a.b.c.tempmail.com is checked as
    # a.b.c.tempmail.com, b.c.tempmail.com, c.tempmail.com and tempmail.com.
    #
    # Trade-off (documented instead of pulling in a full public-suffix-list
    # dependency): the walk never queries single-label suffixes (bare TLDs like
    # "com"), but without a PSL it cannot tell that multi-label suffixes like
    # "co.uk" are public — those candidates are harmless unless a public suffix
    # is deliberately added to the list. Conversely, a throwaway address nested
    # more than 3 labels below a listed domain escapes the walk; blocklisted
    # domains are registrable domains, so 3 levels covers practical abuse.
    PARENT_MATCH_DEPTH = 3

    class << self
      def disposable?(domain)
        return false if domain.blank?

        raw = domain
        domain = Nondisposable::Domain.normalize(raw)
        # Not UTF-8: no list holds it and no mail server can deliver to it.
        return false if domain.encoding == Encoding::BINARY && !domain.ascii_only?
        config = Nondisposable.configuration
        candidates = match_candidates(domain)

        # Host lists go through the same normalisation as the address, so
        # `bücher.de` in excluded_domains still matches `xn--bcher-kva.de`.
        additional = config.additional_domains.map { |d| Nondisposable::Domain.normalize(d) }
        return true if (candidates & additional).any? # rubocop compat: Array#intersect? needs Ruby >= 3.1, gem supports 3.0

        excluded = config.excluded_domains.map { |d| Nondisposable::Domain.normalize(d) }
        # An exact exclusion always wins, so a specific subdomain can be
        # allowlisted even when a parent domain is on the list.
        return false if excluded.include?(domain)

        names = candidates - excluded
        # Rows written before 0.5.0 stored a unicode domain as it came
        # (lowercased, not punycode). Match that spelling too, so upgrading
        # never unblocks them; the next list refresh rewrites them canonically.
        legacy = Nondisposable::Domain.unicode(raw)
        if legacy != domain
          legacy_excluded = config.excluded_domains.map { |d| Nondisposable::Domain.unicode(d) }
          names |= match_candidates(legacy) - legacy_excluded
        end

        where(name: names).exists?
      end

      # The exact domain plus up to PARENT_MATCH_DEPTH parent domains,
      # never descending below two labels (bare TLDs are never candidates).
      def match_candidates(domain)
        return [domain] unless Nondisposable.configuration.check_parent_domains

        labels = domain.split('.')
        candidates = [domain]
        1.upto(PARENT_MATCH_DEPTH) do |depth|
          parent = labels.drop(depth)
          break if parent.size < 2

          candidates << parent.join('.')
        end
        candidates
      end
    end

  end
end
