# frozen_string_literal: true

require 'set'

module Nondisposable
  # Who wins when two lists disagree about a domain. ONE table, used both when
  # an address is checked (#decide) and when the stored list is built
  # (#filter), so the table and the check can never tell different stories:
  #
  #   1. config.excluded_domains   (host)  → allowed
  #   2. data/never_disposable.txt (gem)   → allowed   real providers and ISPs
  #   3. config.additional_domains (host)  → blocked
  #   4. data/privacy_relays.txt   (gem)   → config.block_privacy_relays decides
  #   5. the merged upstream sources       → blocked
  #
  # Before 0.6.0, additional_domains was checked FIRST, so a host could not
  # exclude a domain it had also added. Now the host's exclusion wins: an
  # allowlist entry is the more deliberate statement, and "a real person
  # cannot sign up" is the costlier mistake.
  #
  # Row 2 outranking row 3 is the deliberate trade-off of this table: a host
  # can no longer block a real provider (say `mail.ru`) through
  # additional_domains. That list is for throwaway domains the upstream lists
  # missed; refusing a whole real provider is a business rule, and belongs in
  # the host's own validation where it can say so to the user.
  #
  # HOW EACH ROW MATCHES
  #
  # - excluded_domains: an exact match allows; an excluded parent can never be
  #   the REASON for a block, but a more specific listed subdomain still blocks
  #   (unchanged since 0.3.0).
  # - never_disposable and privacy relays protect their whole namespace
  #   (`bak.rr.com` is covered by `rr.com`), whatever check_parent_domains says:
  #   upstream lists really do carry ISP subdomains like that one.
  # - additional_domains and the stored list follow check_parent_domains.
  # - No public suffix ever matches anything (Nondisposable::PublicSuffix).
  module Precedence
    NEVER_DISPOSABLE_PATH = File.expand_path('../../data/never_disposable.txt', __dir__)
    PRIVACY_RELAYS_PATH = File.expand_path('../../data/privacy_relays.txt', __dir__)
    EMAIL_PROVIDERS_PATH = File.expand_path('../../data/email_providers.txt', __dir__)

    # A syntactically possible DNS name, after Domain.normalize: at least two
    # labels of 1-63 characters, 253 in total, and a final label that is not
    # all digits (that would be an IP address, not a domain). Underscores are
    # tolerated inside labels — they are legal in DNS, if not in hostnames, and
    # rejecting them would only ever make the list shorter, never safer.
    LABEL = /\A[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?\z/

    class << self
      # ---- Checking one address ---------------------------------------------

      # The verdict for a normalized domain, given the stored-list candidates
      # DisposableDomain.match_candidates produced for it:
      #
      #   [:allow, nil]          rows 1, 2 or 4 said no
      #   [:block, nil]          rows 3 or 4 said yes
      #   [:lookup, candidates]  ask the stored list (row 5) about these
      def decide(domain, candidates)
        config = Nondisposable.configuration
        excluded = configured_set(config.excluded_domains)

        return [:allow, nil] if excluded.include?(domain)
        return [:allow, nil] if namespace_hit(domain, never_disposable)

        remaining = candidates.reject { |candidate| excluded.include?(candidate) }

        additional = configured_set(config.additional_domains)
        return [:block, nil] if remaining.any? { |candidate| additional.include?(candidate) }

        # The relay ALLOWANCE covers the whole relay namespace, whatever is
        # excluded: adding an exclusion must never turn an allowed address into
        # a refused one (filter drops every relay-namespace row the same way).
        # Under block_privacy_relays an excluded relay name stops being a
        # reason to block, like any other exclusion.
        relay_names = namespace(domain).select { |name| privacy_relays.include?(name) }
        if relay_names.any?
          return [:allow, nil] unless config.block_privacy_relays
          return [:block, nil] if relay_names.any? { |name| !excluded.include?(name) }
        end

        [:lookup, remaining]
      end

      # ---- Building the stored list -----------------------------------------

      Result = Struct.new(:kept, :dropped) do
        # { reason => [domains] }, for logging.
        def dropped_by_reason
          dropped.group_by { |_domain, reason| reason }.transform_values { |pairs| pairs.map(&:first).sort }
        end
      end

      # Applies the table to a list about to be stored: every upstream domain
      # is first put in Domain.normalize's canonical form, so every write path
      # (fetch, seed, bundled fallback) stores exactly the name a lookup asks
      # for, whoever the caller is. Each then goes through rows 1, 2 and 4 and
      # the validity checks; the host's additional_domains are added through
      # row 2 and the validity checks.
      #
      # Exclusions are exact here, as they always were: the stored list is not
      # where parent-level exclusions take effect, #decide is.
      #
      # host_policy: false applies only the gem's own rules (validity, public
      # suffixes, never-disposable, and relays always dropped), ignoring every
      # host setting. The updater's size guards count that, so their numbers
      # never depend on the host's configuration.
      def filter(domains, host_policy: true)
        config = Nondisposable.configuration
        excluded = host_policy ? configured_set(config.excluded_domains) : Set.new
        block_relays = host_policy && config.block_privacy_relays
        kept = Set.new
        dropped = []

        domains.each do |raw|
          domain = Domain.normalize(raw)
          next if domain.empty?

          reason = invalid_reason(domain) ||
                   (:excluded if excluded.include?(domain)) ||
                   (:never_disposable if namespace_hit(domain, never_disposable)) ||
                   (:privacy_relay if !block_relays && namespace_hit(domain, privacy_relays))
          reason ? dropped << [domain, reason] : kept << domain
        end

        Array(host_policy ? config.additional_domains : []).each do |raw|
          domain = Domain.normalize(raw)
          next if domain.empty? || excluded.include?(domain)

          reason = (invalid_reason(domain) && :invalid_additional_domain) ||
                   (:additional_domain_is_never_disposable if namespace_hit(domain, never_disposable))
          reason ? dropped << [domain, reason] : kept << domain
        end

        Result.new(kept, dropped)
      end

      # nil when `domain` (normalized) may be stored, otherwise why not.
      def invalid_reason(domain)
        return :invalid unless hostname?(domain)
        return :public_suffix if PublicSuffix.public_suffix?(domain)

        nil
      end

      def hostname?(domain)
        return false if domain.empty? || domain.length > 253

        labels = domain.split('.', -1)
        labels.size >= 2 &&
          labels.all? { |label| label.length <= 63 && LABEL.match?(label) } &&
          !labels.last.match?(/\A\d+\z/)
      end

      # ---- The bundled lists -------------------------------------------------

      # data/never_disposable.txt + data/email_providers.txt, minus the relays.
      # Unioned at runtime so a provider added for the typo checks is protected
      # here too, without anybody remembering to copy it.
      def never_disposable
        @never_disposable ||= (read_list(NEVER_DISPOSABLE_PATH) | read_list(EMAIL_PROVIDERS_PATH)).subtract(privacy_relays).freeze
      end

      def privacy_relays
        @privacy_relays ||= read_list(PRIVACY_RELAYS_PATH).freeze
      end

      def reload!
        @never_disposable = nil
        @privacy_relays = nil
        self
      end

      # The domain and each of its parents down to its registrable domain:
      # `a.b.rr.com` => ["a.b.rr.com", "b.rr.com", "rr.com"]. Empty for a public
      # suffix. Never climbs past the registrable domain, so `sch.uk` is not in
      # the namespace of `school.county.sch.uk`.
      def namespace(domain)
        registrable = PublicSuffix.registrable_domain(domain)
        return [] unless registrable

        labels = domain.split('.')
        (0..(labels.size - registrable.count('.') - 1)).map { |i| labels.drop(i).join('.') }
      end

      # The most specific name in `domain`'s namespace that `set` contains.
      def namespace_hit(domain, set)
        namespace(domain).find { |name| set.include?(name) }
      end

      private

      # Host-supplied, so normalized on every read rather than trusted.
      def configured_set(values)
        Array(values).each_with_object(Set.new) do |value, set|
          domain = Domain.normalize(value)
          set << domain unless domain.empty?
        end
      end

      # One domain per line; `#` starts a comment, inline or whole-line.
      def read_list(path)
        File.foreach(path, encoding: 'UTF-8').each_with_object(Set.new) do |line, set|
          domain = Domain.normalize(line.sub(/#.*/, ''))
          set << domain unless domain.empty?
        end
      end
    end
  end
end
