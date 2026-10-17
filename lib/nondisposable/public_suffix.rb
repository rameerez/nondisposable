# frozen_string_literal: true

require 'set'

module Nondisposable
  # Is this domain a PUBLIC SUFFIX — a name under which anybody can register
  # their own domain, like `com`, `co.uk`, `com.br` or `github.io`?
  #
  # WHY THE BLOCKLIST NEEDS TO KNOW
  #
  # Parent-domain matching blocks `x.tempmail.com` because `tempmail.com` is on
  # the list. That is exactly right for a registrable domain and exactly wrong
  # for a public suffix: one bad line reading `com.br` in any upstream list
  # would refuse every Brazilian company's staff, and nothing in a domain count
  # or a file size would look unusual. So no public suffix is ever stored, ever
  # accepted from `additional_domains`, and ever used as a parent-match
  # candidate. That last one matters on its own: it keeps a row written by an
  # older version of this gem from doing any damage either.
  #
  # WHY A BUNDLED SNAPSHOT AND NOT THE `public_suffix` GEM
  #
  # The same reason as Nondisposable::Tld: we need one yes/no answer, offline,
  # on every signup, with no network and no extra runtime dependency. The list
  # is the canonical file from https://publicsuffix.org/list/public_suffix_list.dat
  # (MPL 2.0, redistributed unmodified), ~10,000 rules in ~330 KB, parsed once
  # into frozen Sets. Both sections are honoured: the ICANN section (`co.uk`)
  # and the private one (`github.io`, `blogspot.com`), because in both cases the
  # names below belong to unrelated people. Refresh it with
  # `rake nondisposable:psl:update` when cutting a release.
  #
  # STALENESS
  #
  # A suffix added after the snapshot is simply unknown: we would accept a
  # blocklist entry for it, which is today's behaviour, so a stale snapshot can
  # only ever be less protective, never lock anybody out.
  module PublicSuffix
    LIST_PATH = File.expand_path('../../data/public_suffix_list.dat', __dir__)

    class << self
      # True when `domain` is itself a public suffix. Single-label names (bare
      # TLDs, known or not) always are: that is the PSL's implicit `*` rule.
      # Expects a normalized domain (see Nondisposable::Domain.normalize).
      def public_suffix?(domain)
        domain = domain.to_s
        return false if domain.empty?

        labels = domain.split('.')
        return true if labels.size == 1

        list = rules
        return false if list[:exceptions].include?(domain)
        return true if list[:exact].include?(domain)

        list[:wildcards].include?(labels.drop(1).join('.'))
      end

      # The registrable domain `domain` belongs to: its longest public suffix
      # plus one label. `school.county.sch.uk` => itself (`county.sch.uk` is a
      # suffix via `*.sch.uk`); `x.tempmail.com` => `tempmail.com`. nil when
      # `domain` is itself a public suffix.
      #
      # Everything ABOVE this name belongs to the registry or to unrelated
      # registrants, so no list entry up there may ever match `domain` — not
      # even a name like `sch.uk` that is not itself a suffix but sits above a
      # wildcard one.
      def registrable_domain(domain)
        labels = domain.to_s.split('.')
        return nil if labels.empty? || public_suffix?(domain.to_s)

        # An exception rule prevails (`!city.kawasaki.jp` makes its parent the
        # suffix); otherwise the longest suffix that is public wins.
        exceptions = rules[:exceptions]
        exception = (1..labels.size).find { |n| exceptions.include?(labels.last(n).join('.')) }
        suffix_size = if exception
                        exception - 1
                      else
                        (1...labels.size).select { |n| public_suffix?(labels.last(n).join('.')) }.max || 1
                      end
        labels.last(suffix_size + 1).join('.')
      end

      # IANA-style provenance for health checks: "2026-10-16_23-32-13_UTC".
      def version
        @version ||= begin
          line = File.foreach(LIST_PATH).first(20).find { |l| l.start_with?('// VERSION:') }
          line&.delete_prefix('// VERSION:')&.strip
        rescue StandardError
          nil
        end
      end

      def rule_count
        list = rules
        list[:exact].size + list[:wildcards].size + list[:exceptions].size
      end

      # Reset the memoized rules. Called by the updater after it rewrites the
      # file, and by tests.
      def reload!
        @rules = nil
        @version = nil
        self
      end

      # Parses PSL text into the three rule kinds. Public so the updater can
      # judge a downloaded body before it replaces the bundled one.
      #
      # Rules are stored in their ASCII (punycode) form, because that is the
      # form Domain.normalize produces. A unicode rule we cannot convert is
      # kept as-is: it then simply never matches, which errs towards today's
      # behaviour rather than towards refusing anybody.
      def parse(text)
        exact = Set.new
        wildcards = Set.new
        exceptions = Set.new

        text.each_line do |line|
          rule = line.strip
          next if rule.empty? || rule.start_with?('//')

          rule = rule.split(/\s/, 2).first # the PSL ends a rule at whitespace
          if rule.start_with?('!')
            exceptions << ascii(rule.delete_prefix('!'))
          elsif rule.start_with?('*.')
            wildcards << ascii(rule.delete_prefix('*.'))
          else
            exact << ascii(rule)
          end
        end

        { exact: exact.freeze, wildcards: wildcards.freeze, exceptions: exceptions.freeze }.freeze
      end

      private

      def rules
        @rules ||= parse(File.read(LIST_PATH, encoding: 'UTF-8'))
      end

      def ascii(rule)
        Nondisposable::Domain.normalize(rule)
      rescue StandardError
        rule.downcase
      end
    end
  end
end
