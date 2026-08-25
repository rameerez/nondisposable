# frozen_string_literal: true

require 'set'

module Nondisposable
  # Is the bit after the last dot a real top-level domain?
  #
  # This is a different question from "is this a disposable provider", and it
  # catches a different kind of bad address: the typo. `user@gmail.con` is not a
  # throwaway — it is a real person who will never receive their confirmation
  # email, because `.con` does not exist and never has. Those accounts are born
  # dead: nobody can reach the user, and the user cannot recover the account.
  #
  # WHY A BUNDLED LIST AND NOT A DEPENDENCY
  #
  # The list is the IANA root zone database — the authoritative register of every
  # delegated TLD on the internet, ~1,438 entries in about 9 KB:
  #
  #   https://data.iana.org/TLD/tlds-alpha-by-domain.txt
  #
  # Every "TLD list" repository on GitHub is a scrape of that file, so we go to
  # the source. The `tld` gem last shipped in 2014 and its list predates roughly
  # 1,200 of today's TLDs. `public_suffix` is excellent and alive, but it answers
  # "is this a valid public suffix" (which includes private entries like
  # `github.io`) and it would pull the whole Public Suffix List in as a runtime
  # dependency — the same trade-off DisposableDomain::PARENT_MATCH_DEPTH already
  # declined, for the same reason.
  #
  # WHY IN MEMORY AND NOT IN THE DATABASE
  #
  # Disposable domains live in a table because there are 8,000+ of them and they
  # change every few days. TLDs are 1,438 strings that change a handful of times
  # a year. A frozen Set costs ~100 KB of process memory, answers in O(1) with no
  # query per signup, needs no migration, and — unlike a table — cannot be empty
  # on a fresh install. Refresh it with `rake nondisposable:tlds:update` (or
  # `Nondisposable::TldListUpdater.update`) when cutting a release.
  #
  # STALENESS, AND WHY IT CANNOT LOCK ANYONE OUT
  #
  # The failure mode of a stale list is rejecting somebody whose TLD was
  # delegated after the snapshot. `Nondisposable.configuration.additional_tlds`
  # is the escape hatch: a host can accept a brand-new TLD immediately, without
  # waiting for a gem release. And the check is opt-in (`config.check_tld`), so
  # upgrading the gem never silently starts rejecting anybody.
  module Tld
    # The vendored IANA snapshot. Its first line is IANA's own version header,
    # kept verbatim so the provenance and date of the data ship with it.
    LIST_PATH = File.expand_path('../../data/iana_tlds.txt', __dir__)

    # The names RFC 6761 and RFC 2606 reserve so they can NEVER be delegated.
    # They are therefore absent from the root zone, and `check_tld` rejects
    # them — which is right for a signup form, because no human types
    # `me@home.test`, and an address there could never receive the confirmation
    # email anyway.
    #
    # It is also, on the day you switch `check_tld` on, why half your test suite
    # goes red: fixtures live at `user@example.test` for exactly the same reason
    # the names are reserved. That is a configuration question, not a bug, and
    # this constant is here so the answer reads like a sentence:
    #
    #   config.additional_tlds = Nondisposable::Tld::SPECIAL_USE if Rails.env.local?
    #
    # Scope it to your non-production environments. Somewhere in the world
    # somebody is running an app that really does deliver mail inside `.local`;
    # if that is you, add it in production too and you are the exception that
    # proves why this is configuration.
    SPECIAL_USE = %w[test example invalid localhost local onion].freeze

    class << self
      # Every TLD IANA has delegated, downcased, as a frozen Set.
      # Memoized: read once per process, never re-read.
      def all
        @all ||= parse(File.readlines(LIST_PATH, chomp: true)).freeze
      end

      # IANA's own version string for the bundled snapshot, e.g.
      # "2026082301, Last Updated Mon Aug 24 07:07:01 2026 UTC". Useful in a
      # health check to see how old your list is.
      def version
        @version ||= begin
          header = File.open(LIST_PATH, &:readline).to_s.strip
          header.start_with?('#') ? header.sub(/\A#\s*Version\s*/i, '') : nil
        rescue StandardError
          nil
        end
      end

      # The TLD of an email address or a bare domain, downcased.
      #
      # nil means THERE IS NO TLD HERE — which is not the same as "we can't
      # tell". `example@gmailmcom` (the dot missed entirely) and
      # `you@localhost` both land here, and under check_tld both are rejected:
      # a domain with no TLD cannot end in a real one. Ask #judgeable? first if
      # you need to tell that apart from an address this gem has no opinion on.
      def extract(email_or_domain)
        domain = normalize(email_or_domain)
        return nil if domain.empty?

        labels = domain.split('.')
        return nil if labels.size < 2

        tld = labels.last
        tld.empty? ? nil : tld
      end

      # Is this an address the TLD rules have anything to say about?
      #
      # False for the two shapes where "what is the TLD" is the wrong question
      # rather than a question with a bad answer: an empty domain, and an IP
      # literal (`user@192.168.0.1`, `user@[10.0.0.1]`). Both are left alone —
      # deciding whether to accept an IP-literal address is a format policy, and
      # a validator called `check_tld` has no business making it.
      def judgeable?(email_or_domain)
        domain = normalize(email_or_domain)
        return false if domain.empty?
        return false if domain.start_with?('[') || domain.match?(/\A[\d.]+\z/)

        true
      end

      # Is this TLD in the root zone (or in the host's additional_tlds)?
      #
      # ⚠️ Non-ASCII TLDs always answer true. IANA lists internationalised TLDs
      # in punycode (`XN--FIQS8S`), and converting `中国` to that form needs an
      # IDN library we deliberately do not depend on. Rather than reject every
      # unicode address, we decline to judge them: a false accept is a nuisance,
      # a false reject is a locked-out human. Punycode-form addresses, which is
      # what mail clients actually send, are checked normally.
      def valid?(tld)
        tld = tld.to_s.downcase
        return false if tld.empty?
        return true unless tld.ascii_only?

        all.include?(tld) || configured(:additional_tlds).include?(tld)
      end

      # Has the host explicitly blocked this TLD — either by naming it in
      # `blocked_tlds`, or by naming everything else in `allowed_tlds`?
      def blocked?(tld)
        tld = tld.to_s.downcase
        return false if tld.empty?

        allowed = configured(:allowed_tlds)
        return true if allowed && !allowed.include?(tld)

        configured(:blocked_tlds).include?(tld)
      end

      # Reset the memoized list. Called by the updater after it rewrites the
      # file, and by tests.
      def reload!
        @all = nil
        @version = nil
        self
      end

      private

      # The domain half, trimmed, downcased, and without the trailing dot a
      # fully-qualified name may carry (`gmail.com.` is the same host).
      def normalize(email_or_domain)
        email_or_domain.to_s.split('@').last.to_s.strip.downcase.delete_suffix('.')
      end

      # Skips IANA's comment header and any blank lines.
      def parse(lines)
        lines.each_with_object(Set.new) do |line, set|
          value = line.to_s.strip.downcase
          next if value.empty? || value.start_with?('#')

          set << value
        end
      end

      # Config lists are host-supplied, so normalise on every read rather than
      # trusting them to be lowercase, dotless strings. `.tk` and `TK` both work.
      def configured(key)
        value = Nondisposable.configuration.public_send(key)
        return nil if value.nil?

        Set.new(Array(value).map { |tld| tld.to_s.strip.downcase.delete_prefix('.') })
      end
    end
  end
end
